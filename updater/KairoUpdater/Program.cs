/**
 * KairoUpdater — External update process for Kairo POS
 * 
 * This process is launched by Electron BEFORE it quits.
 * It waits for the Electron PID to die, then replaces files,
 * updates version.json, and relaunches KAIRO POs.exe.
 * 
 * Usage:
 *   kairo-updater.exe --script <path> --pid <electronPid> [--restart]
 */

using System.Diagnostics;
using System.IO.Compression;
using System.Text.Json;
using System.Text.Json.Serialization;

// ── Parse arguments ───────────────────────────────────────────────────────────
string? scriptPath = null;
int     targetPid  = 0;
bool    doRestart  = false;

for (int i = 0; i < args.Length; i++)
{
    switch (args[i].ToLower())
    {
        case "--script":  scriptPath = args[++i]; break;
        case "--pid":     int.TryParse(args[++i], out targetPid); break;
        case "--restart": doRestart = true; break;
    }
}

// ── Setup logging ─────────────────────────────────────────────────────────────
var logDir  = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "KairoPOS", "logs");
Directory.CreateDirectory(logDir);
var logPath = Path.Combine(logDir, "updater.log");

void Log(string msg)
{
    var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {msg}";
    Console.WriteLine(line);
    File.AppendAllText(logPath, line + Environment.NewLine);
}

Log("=== Kairo Updater started ===");
Log($"Script: {scriptPath}");
Log($"Target PID: {targetPid}");

// ── Validate input ────────────────────────────────────────────────────────────
if (string.IsNullOrEmpty(scriptPath) || !File.Exists(scriptPath))
{
    Log("ERROR: update-script.json not found or not specified.");
    Environment.Exit(1);
}

// ── Parse update script ───────────────────────────────────────────────────────
UpdateScript script;
try
{
    var json = File.ReadAllText(scriptPath);
    script = JsonSerializer.Deserialize<UpdateScript>(json, new JsonSerializerOptions
    {
        PropertyNameCaseInsensitive = true
    }) ?? throw new Exception("Script deserialization returned null");
}
catch (Exception ex)
{
    Log($"ERROR: Failed to parse update script: {ex.Message}");
    Environment.Exit(1);
    return;
}

Log($"Updating to version: {script.Version}");

// ── Wait for Electron to exit ─────────────────────────────────────────────────
if (targetPid > 0)
{
    Log($"Waiting for PID {targetPid} to exit...");
    try
    {
        using var proc = Process.GetProcessById(targetPid);
        bool exited = proc.WaitForExit(15_000); // max 15s
        if (!exited)
        {
            Log("WARNING: Process did not exit in 15s. Forcing kill...");
            proc.Kill(true);
            await Task.Delay(2000);
        }
    }
    catch (ArgumentException)
    {
        Log("Process already exited.");
    }
}

await Task.Delay(1000); // extra buffer for file handles to release

// ── Create backup of current binaries ────────────────────────────────────────
var backupDir = Path.Combine(script.AppRoot, "updater", "backup");
Directory.CreateDirectory(backupDir);

foreach (var pkg in script.Packages)
{
    try
    {
        if (pkg.Name == "frontend")
        {
            var asarPath = Path.Combine(pkg.Dest, "app.asar");
            if (File.Exists(asarPath))
            {
                File.Copy(asarPath, Path.Combine(backupDir, "app.asar.bak"), overwrite: true);
                Log($"Backed up: app.asar");
            }
        }
        else if (pkg.Name == "backend")
        {
            var backendBak = Path.Combine(backupDir, "api_bak");
            if (Directory.Exists(backendBak)) Directory.Delete(backendBak, recursive: true);
            if (Directory.Exists(pkg.Dest))
            {
                CopyDirectory(pkg.Dest, backendBak);
                Log($"Backed up: api/ → api_bak/");
            }
        }
    }
    catch (Exception ex)
    {
        Log($"WARNING: Could not backup {pkg.Name}: {ex.Message}");
    }
}

// ── Apply packages ────────────────────────────────────────────────────────────
bool success = true;

foreach (var pkg in script.Packages)
{
    Log($"Applying {pkg.Name} from {pkg.Source}...");
    try
    {
        if (!File.Exists(pkg.Source))
        {
            Log($"  SKIP: {pkg.Source} not found");
            continue;
        }

        Directory.CreateDirectory(pkg.Dest);

        // Extract zip, skipping protected files
        using var zip = ZipFile.OpenRead(pkg.Source);
        foreach (var entry in zip.Entries)
        {
            // Skip directories
            if (string.IsNullOrEmpty(entry.Name)) continue;

            // Check if this file is protected
            bool isProtected = pkg.Protected?.Any(p =>
                entry.FullName.EndsWith(p, StringComparison.OrdinalIgnoreCase)) ?? false;

            if (isProtected)
            {
                Log($"  PROTECTED (skip): {entry.FullName}");
                continue;
            }

            var destPath = Path.Combine(pkg.Dest, entry.FullName);
            Directory.CreateDirectory(Path.GetDirectoryName(destPath)!);

            entry.ExtractToFile(destPath, overwrite: true);
        }

        Log($"  OK: {pkg.Name} applied.");
    }
    catch (Exception ex)
    {
        Log($"  ERROR applying {pkg.Name}: {ex.Message}");
        success = false;
        break;
    }
}

// ── Update version.json ───────────────────────────────────────────────────────
if (success && !string.IsNullOrEmpty(script.VersionJsonPath) && File.Exists(script.VersionJsonPath))
{
    try
    {
        var versionJson = File.ReadAllText(script.VersionJsonPath);
        var dict = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(versionJson) ?? new();
        var mutable = dict.ToDictionary(k => k.Key, v => (object)v.Value.GetRawText().Trim('"'));

        mutable["version"]    = script.Version;
        mutable["channel"]    = "stable"; // Maintain channel if not provided

        File.WriteAllText(script.VersionJsonPath,
            JsonSerializer.Serialize(mutable, new JsonSerializerOptions { WriteIndented = true }));

        Log($"version.json updated to {script.Version}");
    }
    catch (Exception ex)
    {
        Log($"WARNING: Could not update version.json: {ex.Message}");
    }
}

// ── Rollback on failure ───────────────────────────────────────────────────────
if (!success)
{
    Log("ROLLING BACK...");
    try
    {
        // Restore app.asar
        var asarBak = Path.Combine(backupDir, "app.asar.bak");
        var asarDest = script.Packages.FirstOrDefault(p => p.Name == "frontend")?.Dest;
        if (File.Exists(asarBak) && asarDest != null)
        {
            File.Copy(asarBak, Path.Combine(asarDest, "app.asar"), overwrite: true);
            Log("Restored app.asar from backup.");
        }

        // Restore backend
        var backendBak = Path.Combine(backupDir, "api_bak");
        var backendDest = script.Packages.FirstOrDefault(p => p.Name == "backend")?.Dest;
        if (Directory.Exists(backendBak) && backendDest != null)
        {
            if (Directory.Exists(backendDest)) Directory.Delete(backendDest, recursive: true);
            CopyDirectory(backendBak, backendDest);
            Log("Restored api/ from backup.");
        }
    }
    catch (Exception ex)
    {
        Log($"CRITICAL: Rollback failed: {ex.Message}");
    }
}

// ── Clean up download temp files ──────────────────────────────────────────────
try
{
    if (File.Exists(scriptPath)) File.Delete(scriptPath);
    foreach (var pkg in script.Packages)
        if (File.Exists(pkg.Source)) File.Delete(pkg.Source);
}
catch { /* silent */ }

// ── Relaunch app ──────────────────────────────────────────────────────────────
if (doRestart && !string.IsNullOrEmpty(script.AppExe) && File.Exists(script.AppExe))
{
    Log($"Relaunching: {script.AppExe}");
    Process.Start(new ProcessStartInfo
    {
        FileName        = script.AppExe,
        UseShellExecute = true,
    });
}

Log(success ? "=== Update completed successfully ===" : "=== Update failed (rolled back) ===");

// ─── Helpers ──────────────────────────────────────────────────────────────────
static void CopyDirectory(string source, string dest)
{
    Directory.CreateDirectory(dest);
    foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
    {
        var relative = Path.GetRelativePath(source, file);
        var destFile = Path.Combine(dest, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(destFile)!);
        File.Copy(file, destFile, overwrite: true);
    }
}

// ─── Models ───────────────────────────────────────────────────────────────────
record UpdateScript(
    [property: JsonPropertyName("version")]        string Version,
    [property: JsonPropertyName("timestamp")]      string Timestamp,
    [property: JsonPropertyName("appRoot")]        string AppRoot,
    [property: JsonPropertyName("appExe")]         string AppExe,
    [property: JsonPropertyName("versionJsonPath")]string VersionJsonPath,
    [property: JsonPropertyName("packages")]       List<UpdatePackage> Packages
);

record UpdatePackage(
    [property: JsonPropertyName("name")]      string Name,
    [property: JsonPropertyName("source")]    string Source,
    [property: JsonPropertyName("dest")]      string Dest,
    [property: JsonPropertyName("protected")] List<string>? Protected
);
