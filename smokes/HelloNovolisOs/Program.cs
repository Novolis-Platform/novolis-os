using System.Runtime.InteropServices;

var once = args.Contains("--once", StringComparer.OrdinalIgnoreCase)
    || string.Equals(Environment.GetEnvironmentVariable("NOVOLIS_OS_ONCE"), "1", StringComparison.Ordinal);

Console.WriteLine("Novolis OS");
Console.WriteLine("app=HelloNovolisOs");
Console.WriteLine($"runtime={RuntimeInformation.FrameworkDescription}");
Console.WriteLine($"os={RuntimeInformation.OSDescription}");
Console.WriteLine("status=running");

if (once)
{
    Console.WriteLine("status=exited");
    return 0;
}

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cts.Cancel();
};

try
{
    await Task.Delay(Timeout.Infinite, cts.Token);
}
catch (OperationCanceledException)
{
    // shut down
}

Console.WriteLine("status=exited");
return 0;
