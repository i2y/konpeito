# Setup script for Windows: downloads JWM + Skija JARs and compiles KUIRuntime.java
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Find Java tools
$JavaHome = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { "C:\Program Files\Java\jdk-21" }
$Javac = Join-Path $JavaHome "bin\javac.exe"
if (-not (Test-Path $Javac)) {
    $Javac = (Get-Command javac -ErrorAction SilentlyContinue).Source
    if (-not $Javac) {
        Write-Error "javac not found. Install Java 21+: winget install EclipseAdoptium.Temurin.21.JDK"
        exit 1
    }
}

$LibsDir = Join-Path $ScriptDir "lib"
$ClassesDir = Join-Path $ScriptDir "classes"
New-Item -ItemType Directory -Force -Path $LibsDir | Out-Null
New-Item -ItemType Directory -Force -Path $ClassesDir | Out-Null

$JwmVersion = "0.4.8"
$SkijaVersion = "0.116.2"
$SkijaSharedVersion = "0.116.2"
$TypesVersion = "0.2.0"
$SkijaPlatform = "windows-x64"

$MavenBase = "https://repo1.maven.org/maven2/io/github/humbleui"

# Download JWM
$JwmJar = Join-Path $LibsDir "jwm.jar"
if (-not (Test-Path $JwmJar)) {
    Write-Host "Downloading JWM ${JwmVersion}..."
    Invoke-WebRequest -Uri "${MavenBase}/jwm/${JwmVersion}/jwm-${JwmVersion}.jar" -OutFile $JwmJar
} else {
    Write-Host "JWM already downloaded."
}

# Download Skija shared
$SkijaSharedJar = Join-Path $LibsDir "skija-shared.jar"
if (-not (Test-Path $SkijaSharedJar)) {
    Write-Host "Downloading Skija shared ${SkijaSharedVersion}..."
    Invoke-WebRequest -Uri "${MavenBase}/skija-shared/${SkijaSharedVersion}/skija-shared-${SkijaSharedVersion}.jar" -OutFile $SkijaSharedJar
} else {
    Write-Host "Skija shared already downloaded."
}

# Download platform-specific Skija
$SkijaPlatformJar = Join-Path $LibsDir "skija-platform.jar"
if (-not (Test-Path $SkijaPlatformJar)) {
    Write-Host "Downloading Skija (${SkijaPlatform}) ${SkijaVersion}..."
    Invoke-WebRequest -Uri "${MavenBase}/skija-${SkijaPlatform}/${SkijaVersion}/skija-${SkijaPlatform}-${SkijaVersion}.jar" -OutFile $SkijaPlatformJar
} else {
    Write-Host "Skija platform already downloaded."
}

# Download HumbleUI Types
$TypesJar = Join-Path $LibsDir "types.jar"
if (-not (Test-Path $TypesJar)) {
    Write-Host "Downloading Types ${TypesVersion}..."
    Invoke-WebRequest -Uri "${MavenBase}/types/${TypesVersion}/types-${TypesVersion}.jar" -OutFile $TypesJar
} else {
    Write-Host "Types already downloaded."
}

# Compile KUIRuntime.java
Write-Host "Compiling KUIRuntime..."
$Classpath = "${JwmJar};${SkijaSharedJar};${SkijaPlatformJar};${TypesJar}"
$SourceFile = Join-Path $ScriptDir "src\konpeito\ui\KUIRuntime.java"
& $Javac -cp $Classpath -d $ClassesDir $SourceFile

Write-Host ""
Write-Host "Setup complete!"
Write-Host "  JARs:    $LibsDir\"
Write-Host "  Classes: $ClassesDir\"
Write-Host ""
Write-Host "Run the demo: .\run.ps1"
