#:sdk Microsoft.NET.Sdk.Web

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Nodes;

// ---------------------------------------------------------------------------
// The gallery service.
//
// A .NET file-based app: no csproj, run with `dotnet run harness/serve.cs`.
// Local rather than static because launching a prototype means starting a
// process, which no browser page can do however it is delivered. Nothing here
// uploads anything: unreleased game design stays on the machine that made it.
//
// Layout it reads: .harness-out/<game>/<scenario>/<runId>/result.json
// The runId level exists because a scenario has a history. One run says whether
// a prototype works; two say whether a change helped, and the second question is
// the one that drives tuning.
// ---------------------------------------------------------------------------

string repoRoot = ArgValue(args, "--root") ?? Directory.GetCurrentDirectory();
int port = int.TryParse(ArgValue(args, "--port"), out var p) ? p : 7777;
string defaultOut = ArgValue(args, "--out") ?? Path.Combine(repoRoot, ".harness-out");
string defaultStore = ArgValue(args, "--store") ?? Path.Combine(repoRoot, ".harness-verdicts.json");
// Gallery assets sit beside this file, wherever it has been installed. The path
// is captured at compile time via CallerFilePath rather than guessed from the
// working directory, because a file-based app runs from a generated temp
// directory and AppContext.BaseDirectory points there, not at the source.
string galleryDir = ArgValue(args, "--gallery") ?? Path.Combine(SourceDir(), "gallery");
string gamesDirName = ArgValue(args, "--games") ?? "games";
Launcher.Template = ArgValue(args, "--launch");

var builder = WebApplication.CreateBuilder();
builder.Logging.ClearProviders();
var app = builder.Build();

app.MapGet("/health", () => Results.Text("ok"));

// ---- gallery page ---------------------------------------------------------

app.MapGet("/", () => ServeGalleryFile(galleryDir, "index.html", "text/html; charset=utf-8"));
app.MapGet("/gallery.js", () => ServeGalleryFile(galleryDir, "gallery.js", "text/javascript; charset=utf-8"));

// ---- run index ------------------------------------------------------------

app.MapGet("/api/runs", (string? @out, string? store) =>
{
    var runs = RunIndex.Scan(Or(@out, defaultOut));
    Verdicts.Apply(runs, Or(store, defaultStore));
    return Results.Text(RunIndex.ToJson(runs), "application/json");
});

// ---- comparison -----------------------------------------------------------

app.MapGet("/api/compare", (string a, string b, string? @out) =>
{
    var runs = RunIndex.Scan(Or(@out, defaultOut));
    var ra = runs.FirstOrDefault(r => r.Id == a);
    var rb = runs.FirstOrDefault(r => r.Id == b);
    if (ra is null || rb is null)
        return Results.Text(Compare.Refuse("one or both runs are not indexed"), "application/json");
    return Results.Text(Compare.Build(ra, rb), "application/json");
});

// ---- verdicts -------------------------------------------------------------

app.MapPost("/api/verdict", async (HttpRequest req, string? store) =>
{
    using var doc = await JsonDocument.ParseAsync(req.Body);
    string id = doc.RootElement.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? "" : "";
    bool liked = doc.RootElement.TryGetProperty("liked", out var lEl) && lEl.ValueKind == JsonValueKind.True;
    if (id.Length == 0) return Err("id required", 400);
    Verdicts.Set(Or(store, defaultStore), id, liked);
    return Json(new JsonObject { ["id"] = id, ["liked"] = liked });
});

app.MapGet("/api/preferred/{game}", (string game, string? @out, string? store) =>
{
    var runs = RunIndex.Scan(Or(@out, defaultOut));
    Verdicts.Apply(runs, Or(store, defaultStore));
    // Only what the operator actually marked. Never the newest, never the
    // best-measuring: a judgment nobody made must not be invented.
    var preferred = runs.Where(r => r.Game == game && r.Verdict == "liked").ToList();
    return Results.Text(RunIndex.ToJson(preferred), "application/json");
});

// ---- launch ---------------------------------------------------------------
// The only route that executes anything. Validation is against the real games
// directory listing, not string cleaning, because sanitising is a guessing game
// and an enumeration is not.

app.MapPost("/api/launch/{game}", (string game) =>
{
    string gamesRoot = Path.Combine(repoRoot, gamesDirName);
    if (!Directory.Exists(gamesRoot)) return Err("no games directory", 404);

    string? match = Directory.EnumerateDirectories(gamesRoot)
        .Select(Path.GetFileName)
        .FirstOrDefault(n => string.Equals(n, game, StringComparison.Ordinal));
    if (match is null) return Err($"unknown game '{game}'", 404);

    string gameDir = Path.Combine(gamesRoot, match);
    try
    {
        var proc = Launcher.Start(gameDir);
        if (proc is null) return Err("no launch command; pass --launch \"<cmd> {game}\"", 500);
        return Json(new JsonObject { ["pid"] = proc.Id, ["game"] = match });
    }
    catch (Exception e)
    {
        return Err(e.Message, 500);
    }
});

// ---- drift ----------------------------------------------------------------
// What a prototype claims about itself against what it actually did.
//
// Reported per run and never collapsed into one correction factor. Measured
// across three jump strengths the percentage was 11.9 / 9.6 / 6.8 while the
// absolute error held near 12px, because the error is a fixed discretisation
// offset rather than a proportion. A constant fitted at one setting is wrong at
// every other, so none is offered.

app.MapGet("/api/drift/{game}", (string game, string? @out) =>
{
    var runs = RunIndex.Scan(Or(@out, defaultOut)).Where(r => r.Game == game).ToList();
    var arr = new JsonArray();
    foreach (var r in runs.OrderBy(r => r.RunAt))
    {
        // Reported at full working precision and rounded once by whoever
        // displays it. Rounding here too turned 11.8547 into 11.85, which a
        // consumer rounding to one place then took to 11.8 rather than 11.9,
        // because .NET and PowerShell both round half to even.
        double? pct = (r.Measured.HasValue && r.Claimed.HasValue && r.Claimed.Value != 0)
            ? Math.Round((r.Measured.Value - r.Claimed.Value) / r.Claimed.Value * 100.0, 6)
            : (double?)null;
        double? abs = (r.Measured.HasValue && r.Claimed.HasValue)
            ? Math.Round(r.Measured.Value - r.Claimed.Value, 6)
            : (double?)null;
        arr.Add(new JsonObject
        {
            ["runId"] = r.RunId,
            ["scenario"] = r.Scenario,
            ["runAt"] = r.RunAt.ToString("o"),
            ["constant"] = "reach",
            ["claimed"] = r.Claimed,
            ["measured"] = r.Measured,
            ["driftPct"] = pct,
            ["driftAbs"] = abs,
        });
    }
    return Json(new JsonObject { ["game"] = game, ["runs"] = arr });
});

// ---- clips ----------------------------------------------------------------

app.MapGet("/clip/{game}/{scenario}/{runId}/{file}", (string game, string scenario, string runId, string file, string? @out) =>
{
    string root = Or(@out, defaultOut);
    if (!TryResolveContained(root, Path.Combine(game, scenario, runId, file), out string full))
        return Results.NotFound();
    if (!File.Exists(full)) return Results.NotFound();

    string ct = Path.GetExtension(full).ToLowerInvariant() switch
    {
        ".mp4" => "video/mp4",
        ".webm" => "video/webm",
        ".png" => "image/png",
        _ => "application/octet-stream",
    };
    return Results.File(full, ct, enableRangeProcessing: true);
});

app.Run($"http://127.0.0.1:{port}");


// ===========================================================================

static string? ArgValue(string[] argv, string name)
{
    for (int i = 0; i < argv.Length - 1; i++)
        if (argv[i] == name) return argv[i + 1];
    return null;
}

/// <summary>Directory holding this source file, baked in at compile time.</summary>
static string SourceDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path) ?? ".";

static string Or(string? requested, string fallback)
    => string.IsNullOrWhiteSpace(requested) ? fallback : requested;

/// <summary>
/// Every JSON response is built explicitly and returned as text.
///
/// Results.Json and Results.NotFound(object) with an anonymous type compile with
/// only IL2026/IL3050 warnings and then return 500 at runtime here, because
/// reflection-based serialisation is not available in this app. The warnings are
/// real; the failure is invisible until the route is actually called. Building
/// the JsonNode by hand keeps the failure at compile time where it belongs.
/// </summary>
static IResult Json(JsonNode node, int status = 200)
    => Results.Text(node.ToJsonString(), "application/json", null, status);

static IResult Err(string message, int status)
    => Json(new JsonObject { ["error"] = message }, status);

static IResult ServeGalleryFile(string dir, string name, string contentType)
{
    string path = Path.Combine(dir, name);
    return File.Exists(path) ? Results.File(path, contentType) : Results.NotFound();
}

/// <summary>
/// Resolve a caller-supplied relative path against a root and refuse anything
/// landing outside it. The only guard between an HTTP request and the
/// filesystem, so it compares fully-resolved paths rather than looking for ".."
/// in the string, which misses encoded and mixed-separator forms.
/// </summary>
static bool TryResolveContained(string root, string relative, out string full)
{
    full = "";
    try
    {
        string rootFull = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string candidate = Path.GetFullPath(Path.Combine(rootFull, relative));
        if (!candidate.StartsWith(rootFull + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            && !string.Equals(candidate, rootFull, StringComparison.OrdinalIgnoreCase))
            return false;
        full = candidate;
        return true;
    }
    catch { return false; }
}

// ---------------------------------------------------------------------------

sealed class Run
{
    public string Game = "";
    public string Scenario = "";
    public string RunId = "";
    public string Id => $"{Game}/{Scenario}/{RunId}";
    public DateTime RunAt;
    public int Frames;
    public bool Passed;
    public string Reason = "";
    public JsonNode? Checks;
    public JsonNode? Counts;
    public JsonArray Events = new();
    public double? Measured;
    public double? Claimed;
    public string? ClipUrl;
    public string? Verdict;
    public string? PrevRunId;
    public double? DeltaMeasured;
    public JsonObject Claims = new();
    public string Label = "";
    public int CaptureStride = 1;
}

static class RunIndex
{
    public static List<Run> Scan(string outRoot)
    {
        var runs = new List<Run>();
        if (!Directory.Exists(outRoot)) return runs;

        foreach (string gameDir in Directory.EnumerateDirectories(outRoot))
        foreach (string scenDir in Directory.EnumerateDirectories(gameDir))
        foreach (string runDir in Directory.EnumerateDirectories(scenDir))
        {
            string resultPath = Path.Combine(runDir, "result.json");
            // A directory with frames but no result.json is a run that never
            // finished writing. Omit it; a capture still in flight is normal and
            // must not break browsing.
            if (!File.Exists(resultPath)) continue;

            JsonNode? parsed;
            try { parsed = JsonNode.Parse(File.ReadAllText(resultPath)); }
            catch { continue; }
            if (parsed is not JsonObject res) continue;

            var run = new Run
            {
                Game = Path.GetFileName(gameDir),
                Scenario = Path.GetFileName(scenDir),
                RunId = Path.GetFileName(runDir),
                Frames = res["frames"]?.GetValue<int>() ?? 0,
                Passed = res["passed"]?.GetValue<bool>() ?? false,
                Reason = res["reason"]?.GetValue<string>() ?? "",
                Checks = res["checks"]?.DeepClone(),
                Counts = res["counts"]?.DeepClone(),
                Events = res["events"]?.DeepClone() as JsonArray ?? new JsonArray(),
                RunAt = ReadRunAt(res, resultPath),
                Claims = res["claims"]?.DeepClone() as JsonObject ?? new JsonObject(),
                Label = res["label"]?.GetValue<string>() ?? "",
                CaptureStride = res["capture_stride"]?.GetValue<int>() ?? 1,
            };
            // What the prototype says about itself. A claim, not a fact: the
            // whole point of recording it is to check it against the run.
            run.Claimed = ReadClaim(run.Claims, "reach") ?? ReadDouble(res, "claimed");
            run.Measured = ReadDouble(res, "measured")
                        ?? MeasureSpan(run.Events, res["measure"] as JsonObject);
            run.ClipUrl = FindClip(runDir, run);
            runs.Add(run);
        }

        // Newest first. Recorded time, never directory name: names sort lexically
        // and lie about order.
        runs.Sort((x, y) => y.RunAt.CompareTo(x.RunAt));
        LinkPredecessors(runs);
        return runs;
    }

    /// <summary>
    /// Attach each run to the previous run OF THE SAME game and scenario. An
    /// interleaved run of a different scenario is a different input and is not a
    /// predecessor; comparing against it would report a change nobody made.
    /// </summary>
    static void LinkPredecessors(List<Run> runs)
    {
        foreach (var group in runs.GroupBy(r => (r.Game, r.Scenario)))
        {
            var ordered = group.OrderBy(r => r.RunAt).ToList();
            for (int i = 1; i < ordered.Count; i++)
            {
                var cur = ordered[i];
                var prev = ordered[i - 1];
                cur.PrevRunId = prev.RunId;
                if (cur.Measured.HasValue && prev.Measured.HasValue)
                    cur.DeltaMeasured = cur.Measured.Value - prev.Measured.Value;
            }
            // ordered[0] keeps PrevRunId and DeltaMeasured null: a first run has
            // no predecessor, and reporting a delta of zero would read as "no
            // change" rather than "nothing to compare".
        }
    }

    /// <summary>
    /// Distance covered by the first completed span, measured from events rather
    /// than from any formula.
    ///
    /// Which events bound the span is the prototype's business, declared in
    /// result.json as `measure: { from, to, abortOn, axis }`. A platformer says
    /// jump to land aborting on death; a shooter might say fire to impact
    /// aborting on reload. Defaults preserve the platformer vocabulary so
    /// existing runs keep working.
    ///
    /// A span containing the abort event never completed, so it yields nothing.
    /// Pairing across one reported 6.7px of "jump reach" in testing, which is
    /// harmless in a report and destructive when a tuner acts on it.
    /// </summary>
    static double? MeasureSpan(JsonArray events, JsonObject? spec)
    {
        string from = spec?["from"]?.GetValue<string>() ?? "jump";
        string to = spec?["to"]?.GetValue<string>() ?? "land";
        string abortOn = spec?["abortOn"]?.GetValue<string>() ?? "death";
        string axis = spec?["axis"]?.GetValue<string>() ?? "x";

        for (int i = 0; i < events.Count; i++)
        {
            if (events[i]?["name"]?.GetValue<string>() != from) continue;
            double start = events[i]?[axis]?.GetValue<double>() ?? 0;
            for (int k = i + 1; k < events.Count; k++)
            {
                string? n = events[k]?["name"]?.GetValue<string>();
                if (n == abortOn) break;
                if (n != to) continue;
                return (events[k]?[axis]?.GetValue<double>() ?? 0) - start;
            }
        }
        return null;
    }

    public static double? ReadClaim(JsonObject claims, string key)
    {
        var n = claims[key];
        if (n is null) return null;
        try { return n.GetValue<double>(); } catch { return null; }
    }

    static double? ReadDouble(JsonObject res, string key)
    {
        var n = res[key];
        if (n is null) return null;
        try { double v = n.GetValue<double>(); return v == 0 ? null : v; }
        catch { return null; }
    }

    static DateTime ReadRunAt(JsonObject res, string resultPath)
    {
        string? recorded = res["run_at"]?.GetValue<string>();
        if (!string.IsNullOrWhiteSpace(recorded) &&
            DateTime.TryParse(recorded, null, System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal, out var t))
            return t;
        return File.GetLastWriteTimeUtc(resultPath);
    }

    static string? FindClip(string runDir, Run run)
    {
        foreach (string name in new[] { "clip.mp4", "clip.webm" })
            if (File.Exists(Path.Combine(runDir, name)))
                return $"/clip/{run.Game}/{run.Scenario}/{run.RunId}/{name}";
        return null;
    }

    public static string ToJson(List<Run> runs)
    {
        var arr = new JsonArray();
        foreach (var r in runs)
        {
            arr.Add(new JsonObject
            {
                ["id"] = r.Id,
                ["game"] = r.Game,
                ["scenario"] = r.Scenario,
                ["runId"] = r.RunId,
                // A name if the run has one; the id is a timestamp nobody can say
                // out loud or recognise in a list.
                ["label"] = r.Label.Length > 0 ? r.Label : null,
                ["captureStride"] = r.CaptureStride,
                ["runAt"] = r.RunAt.ToString("o"),
                ["frames"] = r.Frames,
                ["passed"] = r.Passed,
                ["reason"] = r.Reason,
                ["checks"] = r.Checks?.DeepClone() ?? new JsonArray(),
                ["counts"] = r.Counts?.DeepClone() ?? new JsonObject(),
                ["events"] = r.Events.DeepClone(),
                ["measured"] = r.Measured,
                ["claimed"] = r.Claimed,
                ["driftPct"] = (r.Measured.HasValue && r.Claimed.HasValue && r.Claimed.Value != 0)
                    ? Math.Round((r.Measured.Value - r.Claimed.Value) / r.Claimed.Value * 100.0, 1)
                    : (double?)null,
                ["driftAbs"] = (r.Measured.HasValue && r.Claimed.HasValue)
                    ? Math.Round(r.Measured.Value - r.Claimed.Value, 1)
                    : (double?)null,
                ["clip"] = r.ClipUrl,
                ["verdict"] = r.Verdict,
                ["prevRunId"] = r.PrevRunId,
                ["deltaMeasured"] = r.DeltaMeasured.HasValue ? Math.Round(r.DeltaMeasured.Value, 3) : (double?)null,
            });
        }
        return arr.ToJsonString();
    }
}

static class Compare
{
    public static string Refuse(string reason)
        => new JsonObject { ["comparable"] = false, ["reason"] = reason }.ToJsonString();

    public static string Build(Run a, Run b)
    {
        // Frame-locking is only meaningful within one scenario: two tapes are two
        // different inputs, so a difference between them says nothing about a change.
        if (a.Game != b.Game || a.Scenario != b.Scenario)
            return Refuse($"different scenario: {a.Game}/{a.Scenario} vs {b.Game}/{b.Scenario}");

        var rows = new JsonArray();
        AddRow(rows, "measured", a.Measured, b.Measured, 1);
        AddRow(rows, "claimed", a.Claimed, b.Claimed, 1);
        AddRow(rows, "frames", a.Frames, b.Frames, 0);

        // Whatever kinds these runs actually recorded, rather than a list baked
        // in for one genre. A shooter emits hits and reloads; a platformer emits
        // jumps and deaths. This tool should not need to know which it is looking at.
        foreach (string kind in EventKinds(a, b))
            AddRow(rows, kind, CountOf(a, kind), CountOf(b, kind), 0);

        return new JsonObject
        {
            ["comparable"] = true,
            ["a"] = a.Id,
            ["b"] = b.Id,
            ["rows"] = rows,
        }.ToJsonString();
    }

    /// <summary>Event kinds present across both runs, minus ones carrying no gameplay meaning.</summary>
    static readonly string[] Ignored = { "note" };

    static List<string> EventKinds(params Run[] runs)
    {
        var set = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var r in runs)
            foreach (var e in r.Events)
            {
                string? n = e?["name"]?.GetValue<string>();
                if (n is not null && Array.IndexOf(Ignored, n) < 0) set.Add(n);
            }
        return set.ToList();
    }

    static double? CountOf(Run r, string name)
    {
        int n = 0;
        foreach (var e in r.Events)
            if (e?["name"]?.GetValue<string>() == name) n++;
        return n;
    }

    static void AddRow(JsonArray rows, string metric, double? a, double? b, int dp)
    {
        rows.Add(new JsonObject
        {
            ["metric"] = metric,
            ["a"] = a,
            ["b"] = b,
            ["delta"] = (a.HasValue && b.HasValue) ? Math.Round(b.Value - a.Value, 3) : (double?)null,
            ["dp"] = dp,
        });
    }
}

static class Verdicts
{
    /// <summary>
    /// Verdicts live outside .harness-out on purpose. Every measurement in there
    /// can be recomputed by re-running; a human judgment about whether something
    /// is fun cannot, and .harness-out is gitignored and routinely deleted.
    /// </summary>
    public static void Set(string storePath, string runId, bool liked)
    {
        var map = Load(storePath);
        if (liked) map[runId] = "liked";
        else map.Remove(runId);

        var obj = new JsonObject();
        foreach (var kv in map) obj[kv.Key] = kv.Value;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(storePath))!);
        File.WriteAllText(storePath, obj.ToJsonString());
    }

    public static void Apply(List<Run> runs, string storePath)
    {
        var map = Load(storePath);
        foreach (var r in runs)
            if (map.TryGetValue(r.Id, out var v)) r.Verdict = v;
    }

    static Dictionary<string, string> Load(string storePath)
    {
        var map = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!File.Exists(storePath)) return map;
        try
        {
            if (JsonNode.Parse(File.ReadAllText(storePath)) is JsonObject o)
                foreach (var kv in o)
                    if (kv.Value is not null) map[kv.Key] = kv.Value.GetValue<string>();
        }
        catch { }
        return map;
    }
}

static class Launcher
{
    /// <summary>
    /// Command template used to start a prototype, with {game} standing for its
    /// directory. Set with --launch so this tool is not tied to one engine:
    ///   --launch "godot --path {game}"
    ///   --launch "love {game}"
    ///   --launch "cargo run --manifest-path {game}/Cargo.toml"
    /// Left null, it falls back to finding Godot on PATH.
    /// </summary>
    public static string? Template;

    public static Process? Start(string gameDir)
    {
        if (!string.IsNullOrWhiteSpace(Template))
        {
            string cmd = Template!.Replace("{game}", gameDir);
            var shell = new ProcessStartInfo
            {
                FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe",
                UseShellExecute = false,
                WorkingDirectory = gameDir,
                // Raw Arguments, NOT ArgumentList. ArgumentList quotes each entry,
                // producing cmd /c "mkdir C:\path", and cmd then tries to read that
                // quoted string as an executable name and does nothing. Here the
                // shell is supposed to parse the command, so it must arrive unquoted.
                Arguments = "/c " + cmd,
            };
            return Process.Start(shell);
        }
        return StartGodot(gameDir);
    }

    static Process? StartGodot(string gameDir)
    {
        string? godot = ResolveOnPath("godot.exe", "godot.cmd", "godot.bat", "godot");
        if (godot is null) return null;

        var psi = new ProcessStartInfo { UseShellExecute = false, WorkingDirectory = gameDir };
        if (godot.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
        {
            psi.FileName = godot;
            psi.ArgumentList.Add("--path");
            psi.ArgumentList.Add(gameDir);
        }
        else
        {
            // A .cmd shim cannot be executed directly with UseShellExecute=false;
            // it is a script, not a Win32 image. cmd.exe stays alive for as long
            // as the game runs, so the returned pid remains meaningful.
            psi.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
            psi.ArgumentList.Add("/c");
            psi.ArgumentList.Add(godot);
            psi.ArgumentList.Add("--path");
            psi.ArgumentList.Add(gameDir);
        }
        return Process.Start(psi);
    }

    static string? ResolveOnPath(params string[] names)
    {
        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (string dir in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        foreach (string n in names)
        {
            try
            {
                string candidate = Path.Combine(dir.Trim('"'), n);
                if (File.Exists(candidate)) return candidate;
            }
            catch { }
        }
        return null;
    }
}
