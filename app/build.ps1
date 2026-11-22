# Builds FireAshCompanion.apk without Gradle (aapt2 + javac + d8 + apksigner).
#
# Needs: JDK 17+ and an Android SDK with "build-tools;34.0.0" and "platforms;android-34".
#   -Sdk  defaults to $env:ANDROID_HOME, then $env:ANDROID_SDK_ROOT
#   -Jdk  defaults to $env:JAVA_HOME (java/javac/keytool on PATH also work)
# A local signing key (companion.keystore, git-ignored) is created on the first build.
param(
  [string]$Sdk = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }),
  [string]$Jdk = $env:JAVA_HOME,
  [string]$BuildTools = '34.0.0',
  [string]$Platform = 'android-34'
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $Sdk -or -not (Test-Path $Sdk)) { throw 'Android SDK not found: pass -Sdk or set ANDROID_HOME' }
if ($Jdk) { $env:JAVA_HOME = $Jdk; $env:Path = "$Jdk\bin;$env:Path" }
$bt  = Join-Path $Sdk "build-tools\$BuildTools"
$jar = Join-Path $Sdk "platforms\$Platform\android.jar"
$out = Join-Path $here 'build'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$out\classes", "$out\dex" | Out-Null

& "$bt\aapt2.exe" compile --dir "$here\res" -o "$out\res.zip"
if ($LASTEXITCODE) { throw 'aapt2 compile failed' }
& "$bt\aapt2.exe" link -o "$out\base.apk" -I $jar --manifest "$here\AndroidManifest.xml" -A "$here\assets" "$out\res.zip" --auto-add-overlay
if ($LASTEXITCODE) { throw 'aapt2 link failed' }

$src = Get-ChildItem "$here\src" -Recurse -Filter *.java | ForEach-Object FullName
& javac -source 11 -target 11 -encoding UTF-8 -classpath $jar -d "$out\classes" $src 2>&1 | Where-Object { $_ -notmatch 'bootstrap classpath|warning: \[options\]|^1 warning' }
if ($LASTEXITCODE) { throw 'javac failed' }
$classes = Get-ChildItem "$out\classes" -Recurse -Filter *.class | ForEach-Object FullName
& "$bt\d8.bat" --min-api 30 --lib $jar --output "$out\dex" $classes
if ($LASTEXITCODE) { throw 'd8 failed' }

# add classes.dex to the APK
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open("$out\base.apk", 'Update')
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$out\dex\classes.dex", 'classes.dex') | Out-Null
$zip.Dispose()

& "$bt\zipalign.exe" -f -p 4 "$out\base.apk" "$out\aligned.apk"
$ks = Join-Path $here 'companion.keystore'
if (-not (Test-Path $ks)) {
  & keytool -genkeypair -keystore $ks -storepass companion -keypass companion -alias companion -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Fire Ash Companion" 2>&1 | Out-Null
}
& "$bt\apksigner.bat" sign --ks $ks --ks-pass pass:companion --key-pass pass:companion --out "$here\FireAshCompanion.apk" "$out\aligned.apk"
if ($LASTEXITCODE) { throw 'apksigner failed' }
Get-Item "$here\FireAshCompanion.apk" | Select-Object Name, Length
