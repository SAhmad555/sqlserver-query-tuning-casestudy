// TuningBench - runs every scenario's before/after script N times against SQL Server and records
// logical reads, CPU time and elapsed time, then captures the actual execution plans.
//
//   dotnet run -c Release --project bench/TuningBench -- [--server "(localdb)\MSSQLLocalDB"]
//        [--database TuningDemo] [--runs 5] [--scenario 03] [--no-plans]
//
// Measurement method
//   * One dedicated connection (pooling off) per phase, so session counters start clean.
//   * <phase>_setup.sql (optional) runs once, unmeasured - e.g. create/drop an index, prime a plan.
//   * One warm-up execution is discarded (warm buffer pool, compiled plan), then N measured runs.
//   * CPU ms and logical reads = delta of sys.dm_exec_sessions (cpu_time, logical_reads) for the
//     benchmark's own session around each run. Unlike SET STATISTICS IO/TIME this also works for
//     cursors / loops that run thousands of statements, and it is the same number the server bills
//     to the session.
//   * Elapsed ms = client-side Stopwatch around ExecuteReader + reading every row (what the
//     application would experience).
//   * Plans: one extra execution with SET STATISTICS XML ON; each actual plan is saved as a
//     .sqlplan file that opens in SSMS / Azure Data Studio / Plan Explorer.

using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

var opts = Options.Parse(args);
var root = FindRepoRoot();
var scenariosDir = Path.Combine(root, "scenarios");
var resultsDir = Directory.CreateDirectory(Path.Combine(root, "results")).FullName;
var plansDir = Directory.CreateDirectory(Path.Combine(root, "plans")).FullName;

var csb = new SqlConnectionStringBuilder
{
    DataSource = opts.Server,
    InitialCatalog = opts.Database,
    IntegratedSecurity = true,
    TrustServerCertificate = true,
    Pooling = false,
    ApplicationName = "TuningBench",
    CommandTimeout = 0
};

Console.WriteLine($"TuningBench  server={opts.Server}  db={opts.Database}  runs={opts.Runs}");
var env = ReadEnvironment(csb.ConnectionString);
Console.WriteLine(env.Version.Split('\n')[0].Trim());

var allRuns = new List<RunResult>();
var summaries = new List<Summary>();

foreach (var dir in Directory.GetDirectories(scenariosDir).OrderBy(d => d, StringComparer.Ordinal))
{
    var name = Path.GetFileName(dir);
    if (opts.Scenario is not null && !name.StartsWith(opts.Scenario, StringComparison.OrdinalIgnoreCase)) continue;
    var title = ReadTitle(dir) ?? name;
    Console.WriteLine();
    Console.WriteLine($"== {name}: {title}");

    var phaseStats = new Dictionary<string, PhaseStats>();
    foreach (var phase in new[] { "before", "after" })
    {
        var script = File.ReadAllText(Path.Combine(dir, $"{phase}.sql"));
        var setupPath = Path.Combine(dir, $"{phase}_setup.sql");

        using var conn = new SqlConnection(csb.ConnectionString);
        conn.Open();

        if (File.Exists(setupPath)) Execute(conn, File.ReadAllText(setupPath));
        Execute(conn, script); // warm-up, discarded

        var runs = new List<RunResult>();
        for (int i = 1; i <= opts.Runs; i++)
        {
            var s0 = Snapshot(conn);
            var sw = Stopwatch.StartNew();
            Execute(conn, script);
            sw.Stop();
            var s1 = Snapshot(conn);
            var r = new RunResult(name, phase, i, sw.Elapsed.TotalMilliseconds,
                                  s1.CpuMs - s0.CpuMs, s1.LogicalReads - s0.LogicalReads, s1.Writes - s0.Writes);
            runs.Add(r);
            Console.WriteLine($"   {phase,-6} run {i}: elapsed {r.ElapsedMs,10:N1} ms   cpu {r.CpuMs,8:N0} ms   logical reads {r.LogicalReads,12:N0}");
        }
        allRuns.AddRange(runs);
        phaseStats[phase] = new PhaseStats(
            Median(runs.Select(r => r.ElapsedMs)),
            Median(runs.Select(r => (double)r.CpuMs)),
            Median(runs.Select(r => (double)r.LogicalReads)));

        if (!opts.NoPlans)
        {
            var files = CapturePlans(conn, script, plansDir, $"{name}__{phase}");
            Console.WriteLine($"   {phase,-6} plans: {string.Join(", ", files)}");
        }
    }
    summaries.Add(new Summary(name, title, phaseStats["before"], phaseStats["after"]));
}

WriteCsv(Path.Combine(resultsDir, "results.csv"), allRuns);
WriteSummaryCsv(Path.Combine(resultsDir, "summary.csv"), summaries);
WriteMarkdown(Path.Combine(resultsDir, "results.md"), summaries, env, opts);
Console.WriteLine();
Console.WriteLine($"Results written to {resultsDir}");
return 0;

// ---------------------------------------------------------------------------------------------

static void Execute(SqlConnection conn, string script)
{
    foreach (var batch in SplitBatches(script))
    {
        using var cmd = new SqlCommand(batch, conn) { CommandTimeout = 0 };
        using var rdr = cmd.ExecuteReader();
        do { while (rdr.Read()) { } } while (rdr.NextResult());
    }
}

static IEnumerable<string> SplitBatches(string script) =>
    Regex.Split(script, @"^\s*GO\s*;?\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase)
         .Where(b => !string.IsNullOrWhiteSpace(StripComments(b)));

static string StripComments(string sql) =>
    Regex.Replace(Regex.Replace(sql, @"/\*.*?\*/", "", RegexOptions.Singleline), @"--[^\r\n]*", "");

static SessionSnapshot Snapshot(SqlConnection conn)
{
    using var cmd = new SqlCommand(
        "SELECT cpu_time, logical_reads, writes FROM sys.dm_exec_sessions WHERE session_id = @@SPID;", conn);
    using var r = cmd.ExecuteReader();
    r.Read();
    return new SessionSnapshot(r.GetInt32(0), r.GetInt64(1), r.GetInt64(2));
}

// Runs the script once with SET STATISTICS XML ON and writes each actual plan to a .sqlplan file.
// Statements that execute many times (cursor loops) are de-duplicated: the first actual plan of
// each distinct statement is kept, and capture stops after a bounded number of plans.
static List<string> CapturePlans(SqlConnection conn, string script, string plansDir, string prefix)
{
    const int maxPlanResultSets = 60;
    foreach (var old in Directory.GetFiles(plansDir, prefix + "*.sqlplan")) File.Delete(old);

    var plans = new List<string>();
    var seen = new HashSet<string>();
    int planSets = 0;
    bool stopped = false;

    using (var on = new SqlCommand("SET STATISTICS XML ON;", conn)) on.ExecuteNonQuery();
    try
    {
        foreach (var batch in SplitBatches(script))
        {
            using var cmd = new SqlCommand(batch, conn) { CommandTimeout = 0 };
            using var rdr = cmd.ExecuteReader();
            do
            {
                bool isPlan = rdr.FieldCount == 1 && rdr.GetName(0).Contains("Showplan", StringComparison.OrdinalIgnoreCase);
                while (rdr.Read())
                {
                    if (!isPlan) continue;
                    planSets++;
                    var xml = rdr.GetString(0);
                    var stmt = Regex.Match(xml, "StatementText=\"([^\"]*)\"").Groups[1].Value;
                    if (seen.Add(stmt)) plans.Add(xml);
                }
                if (planSets >= maxPlanResultSets) { stopped = true; cmd.Cancel(); break; }
            } while (rdr.NextResult());
            if (stopped) break;
        }
    }
    catch (SqlException) when (stopped) { /* cancelled on purpose after enough plans */ }

    if (conn.State == System.Data.ConnectionState.Open && !stopped)
        using (var off = new SqlCommand("SET STATISTICS XML OFF;", conn)) off.ExecuteNonQuery();

    // Skip trivial plans of SET / variable assignments etc. when there is something more interesting.
    var interesting = plans.Where(p => p.Contains("<RelOp", StringComparison.Ordinal)).ToList();
    if (interesting.Count > 0) plans = interesting;

    var files = new List<string>();
    for (int i = 0; i < plans.Count; i++)
    {
        var file = plans.Count == 1 ? $"{prefix}.sqlplan" : $"{prefix}_{i + 1}.sqlplan";
        File.WriteAllText(Path.Combine(plansDir, file), plans[i], new UTF8Encoding(false));
        files.Add(file);
    }
    return files;
}

static EnvInfo ReadEnvironment(string cs)
{
    using var conn = new SqlConnection(cs);
    conn.Open();
    using var cmd = new SqlCommand(@"
        SELECT @@VERSION,
               CAST(SERVERPROPERTY('Edition') AS nvarchar(128)),
               CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)),
               (SELECT cpu_count FROM sys.dm_os_sys_info),
               (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info),
               (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()),
               (SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = 'max degree of parallelism'),
               (SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = 'cost threshold for parallelism');", conn);
    using var r = cmd.ExecuteReader();
    r.Read();
    string cpuName = Environment.ProcessorCount + " logical processors";
    try
    {
        if (OperatingSystem.IsWindows())
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
            if (key?.GetValue("ProcessorNameString") is string s) cpuName = s.Trim() + $" ({Environment.ProcessorCount} logical processors)";
        }
    }
    catch { /* informational only */ }
    return new EnvInfo(r.GetString(0), r.GetString(1), r.GetString(2), r.GetInt32(3), r.GetInt64(4),
                       r.GetByte(5), r.GetInt32(6), r.GetInt32(7), cpuName,
                       System.Runtime.InteropServices.RuntimeInformation.OSDescription);
}

static double Median(IEnumerable<double> values)
{
    var v = values.OrderBy(x => x).ToArray();
    return v.Length % 2 == 1 ? v[v.Length / 2] : (v[v.Length / 2 - 1] + v[v.Length / 2]) / 2.0;
}

static string? ReadTitle(string dir)
{
    var readme = Path.Combine(dir, "README.md");
    if (!File.Exists(readme)) return null;
    var first = File.ReadLines(readme).FirstOrDefault(l => l.StartsWith("# "));
    return first?[2..].Trim();
}

static string FindRepoRoot()
{
    var d = new DirectoryInfo(AppContext.BaseDirectory);
    while (d is not null && !Directory.Exists(Path.Combine(d.FullName, "scenarios"))) d = d.Parent;
    if (d is null)
    {
        d = new DirectoryInfo(Directory.GetCurrentDirectory());
        while (d is not null && !Directory.Exists(Path.Combine(d.FullName, "scenarios"))) d = d.Parent;
    }
    return d?.FullName ?? throw new InvalidOperationException("Could not find the repository root (folder containing 'scenarios').");
}

static string Pct(double before, double after)
{
    if (before <= 0) return "n/a";
    var p = (before - after) / before * 100;
    return p.ToString(p >= 99.95 ? "0.00" : "0.0", CultureInfo.InvariantCulture) + "%";
}

static string Factor(double before, double after) =>
    after <= 0 ? (before <= 0 ? "n/a" : "inf") : (before / after).ToString(before / after >= 100 ? "N0" : "0.0", CultureInfo.InvariantCulture) + "x";

static string F(double v) => v.ToString(v >= 100 ? "N0" : "0.#", CultureInfo.InvariantCulture);

static void WriteCsv(string path, List<RunResult> runs)
{
    var sb = new StringBuilder("scenario,phase,run,elapsed_ms,cpu_ms,logical_reads,writes\n");
    foreach (var r in runs)
        sb.AppendLine(string.Join(',', r.Scenario, r.Phase, r.Run,
            r.ElapsedMs.ToString("0.00", CultureInfo.InvariantCulture), r.CpuMs, r.LogicalReads, r.Writes));
    File.WriteAllText(path, sb.ToString());
}

static void WriteSummaryCsv(string path, List<Summary> s)
{
    var sb = new StringBuilder("scenario,before_elapsed_ms,after_elapsed_ms,before_cpu_ms,after_cpu_ms,before_logical_reads,after_logical_reads,elapsed_improvement_pct,reads_improvement_pct\n");
    foreach (var x in s)
        sb.AppendLine(string.Join(',', x.Scenario,
            x.Before.ElapsedMs.ToString("0.00", CultureInfo.InvariantCulture), x.After.ElapsedMs.ToString("0.00", CultureInfo.InvariantCulture),
            x.Before.CpuMs, x.After.CpuMs, x.Before.LogicalReads, x.After.LogicalReads,
            Pct(x.Before.ElapsedMs, x.After.ElapsedMs).TrimEnd('%'), Pct(x.Before.LogicalReads, x.After.LogicalReads).TrimEnd('%')));
    File.WriteAllText(path, sb.ToString());
}

static void WriteMarkdown(string path, List<Summary> s, EnvInfo e, Options o)
{
    var sb = new StringBuilder();
    sb.AppendLine("# Benchmark results");
    sb.AppendLine();
    sb.AppendLine($"Generated by `bench/TuningBench` on {DateTime.Now:yyyy-MM-dd HH:mm}. Median of {o.Runs} measured runs per phase after one discarded warm-up run (warm buffer pool).");
    sb.AppendLine();
    sb.AppendLine("| # | Scenario | Elapsed ms before → after | CPU ms before → after | Logical reads before → after | Elapsed improvement | Reads improvement |");
    sb.AppendLine("|---|---|---|---|---|---|---|");
    foreach (var x in s)
    {
        sb.AppendLine($"| {x.Scenario[..2]} | {x.Title} | {F(x.Before.ElapsedMs)} → {F(x.After.ElapsedMs)} | {F(x.Before.CpuMs)} → {F(x.After.CpuMs)} | " +
                      $"{F(x.Before.LogicalReads)} → {F(x.After.LogicalReads)} | {Pct(x.Before.ElapsedMs, x.After.ElapsedMs)} ({Factor(x.Before.ElapsedMs, x.After.ElapsedMs)}) | " +
                      $"{Pct(x.Before.LogicalReads, x.After.LogicalReads)} ({Factor(x.Before.LogicalReads, x.After.LogicalReads)}) |");
    }
    sb.AppendLine();
    sb.AppendLine("## Environment");
    sb.AppendLine();
    sb.AppendLine($"- SQL Server: {e.Edition}, version {e.ProductVersion}, database compatibility level {e.CompatLevel}");
    sb.AppendLine($"- Server-visible CPUs: {e.CpuCount}; physical memory: {e.MemoryMb:N0} MB; MAXDOP {e.Maxdop}; cost threshold for parallelism {e.CostThreshold}");
    sb.AppendLine($"- Host CPU: {e.CpuName}");
    sb.AppendLine($"- OS: {e.Os}");
    sb.AppendLine();
    sb.AppendLine("```");
    sb.AppendLine(e.Version.Trim());
    sb.AppendLine("```");
    sb.AppendLine();
    sb.AppendLine("## Method");
    sb.AppendLine();
    sb.AppendLine("- CPU ms and logical reads: delta of `sys.dm_exec_sessions.cpu_time` / `logical_reads` for the benchmark's own session around each run.");
    sb.AppendLine("- Elapsed ms: client-side `Stopwatch` around execution including reading all rows.");
    sb.AppendLine("- `cpu_time` is reported by Windows in ~15.6 ms ticks, so very fast queries show 0 or 15-16 ms CPU; logical reads are exact.");
    sb.AppendLine("- Warm cache: logical reads are independent of caching; elapsed times on a cold cache (physical I/O) would be higher for the 'before' queries.");
    sb.AppendLine("- Raw per-run numbers: [`results.csv`](results.csv); medians: [`summary.csv`](summary.csv).");
    File.WriteAllText(path, sb.ToString());
}

record RunResult(string Scenario, string Phase, int Run, double ElapsedMs, int CpuMs, long LogicalReads, long Writes);
record SessionSnapshot(int CpuMs, long LogicalReads, long Writes);
record PhaseStats(double ElapsedMs, double CpuMs, double LogicalReads);
record Summary(string Scenario, string Title, PhaseStats Before, PhaseStats After);
record EnvInfo(string Version, string Edition, string ProductVersion, int CpuCount, long MemoryMb, byte CompatLevel,
               int Maxdop, int CostThreshold, string CpuName, string Os);

sealed class Options
{
    public string Server { get; private set; } = @"(localdb)\MSSQLLocalDB";
    public string Database { get; private set; } = "TuningDemo";
    public int Runs { get; private set; } = 5;
    public string? Scenario { get; private set; }
    public bool NoPlans { get; private set; }

    public static Options Parse(string[] args)
    {
        var o = new Options();
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "--server": o.Server = args[++i]; break;
                case "--database": o.Database = args[++i]; break;
                case "--runs": o.Runs = int.Parse(args[++i], CultureInfo.InvariantCulture); break;
                case "--scenario": o.Scenario = args[++i]; break;
                case "--no-plans": o.NoPlans = true; break;
                default: throw new ArgumentException($"Unknown argument {args[i]}");
            }
        }
        return o;
    }
}
