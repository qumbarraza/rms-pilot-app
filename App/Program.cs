using System.Reflection;
using RmsPilot.Shared;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var pilotEnv = Environment.GetEnvironmentVariable("PILOT_ENV") ?? "unknown";
var appVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "unknown";

app.MapGet("/", () => new
{
    environment = pilotEnv,
    appVersion,
    sharedLibVersion = Greeter.Version,
    greeting = Greeter.Greet("RMS pilot"),
    timestamp = DateTime.UtcNow
});

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();
