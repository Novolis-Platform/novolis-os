// Enforce Novolis OS package allowlists and budgets.
//
//   dotnet run --file d:\novolis\novolis-os\scripts\Verify-PackageBudget.cs

#:property TargetFramework=net10.0
#:property PublishAot=false
#:property PackAsTool=false
#:property ImplicitUsings=enable
#:property Nullable=enable
#:property ManagePackageVersionsCentrally=false

using System.Runtime.CompilerServices;

var scripts = Path.GetDirectoryName(ThisFile())!;
var repoRoot = Arg(args, "--repo", "-RepoRoot") ?? Directory.GetParent(scripts)!.FullName;
var resolvedPath = Arg(args, "--resolved", "-ResolvedPackagesPath");
var manifestDir = Path.Combine(repoRoot, "manifests");
var manifestFiles = new[] { "base.txt", "dotnet.txt", "ui-graphics.txt", "audio-alsa.txt", "appliance.txt" };
var excludes = ReadList(Path.Combine(manifestDir, "excludes.txt"));
var allExplicit = manifestFiles.SelectMany(f => ReadList(Path.Combine(manifestDir, f))).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
const int maxExplicit = 80;
const int maxResolved = 280;
var failures = new List<string>();
if (allExplicit.Length > maxExplicit)
    failures.Add($"Explicit packages: {allExplicit.Length} > budget {maxExplicit}");
foreach (var pkg in allExplicit)
{
    if (excludes.Any(p => Matches(pkg, p)))
        failures.Add($"Allowlist package '{pkg}' matches hard exclude");
}

if (string.IsNullOrWhiteSpace(resolvedPath))
{
    var candidate = Path.Combine(repoRoot, "artifacts", "resolved-packages.txt");
    if (File.Exists(candidate))
        resolvedPath = candidate;
}

Console.WriteLine("Novolis OS package budget (single profile)");
Console.WriteLine($"  explicit : {allExplicit.Length} / {maxExplicit}");
if (!string.IsNullOrWhiteSpace(resolvedPath) && File.Exists(resolvedPath))
{
    var resolved = ReadList(resolvedPath);
    Console.WriteLine($"  resolved : {resolved.Count} / {maxResolved}");
    if (resolved.Count > maxResolved)
        failures.Add($"Resolved packages: {resolved.Count} > budget {maxResolved}");
    foreach (var pkg in resolved)
    {
        if (excludes.Any(p => Matches(pkg, p)))
            failures.Add($"Resolved package '{pkg}' matches hard exclude");
    }
}
else
{
    Console.WriteLine("  resolved : (no artifacts/resolved-packages.txt yet)");
}

if (failures.Count > 0)
{
    Console.Error.WriteLine("Package budget failed:");
    foreach (var f in failures)
        Console.Error.WriteLine($"  - {f}");
    return 1;
}

Console.WriteLine("OK — allowlists within budget and clear of hard excludes.");
return 0;

static List<string> ReadList(string path) =>
    File.Exists(path)
        ? File.ReadAllLines(path).Select(l => l.Trim()).Where(l => l.Length > 0 && !l.StartsWith('#')).ToList()
        : throw new FileNotFoundException($"Missing package list: {path}");

static bool Matches(string name, string pattern) =>
    pattern.Contains('*')
        ? System.Text.RegularExpressions.Regex.IsMatch(name, "^" + System.Text.RegularExpressions.Regex.Escape(pattern).Replace("\\*", ".*") + "$")
        : string.Equals(name, pattern, StringComparison.OrdinalIgnoreCase);

static string? Arg(string[] args, params string[] names)
{
    for (var i = 0; i < args.Length; i++)
    {
        if (names.Any(n => string.Equals(args[i], n, StringComparison.OrdinalIgnoreCase)) && i + 1 < args.Length)
            return args[i + 1];
    }

    return null;
}

static string ThisFile([CallerFilePath] string path = "") => path;
