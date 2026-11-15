param([string]$NetLogoHome = 'C:/Program Files/NetLogo 7.0.3')
$ErrorActionPreference = 'Stop'
$buildDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('mobile-money-checks-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $buildDirectory | Out-Null
$classpath = Join-Path $NetLogoHome 'app/*'
& javac -cp $classpath -d $buildDirectory (Join-Path $PSScriptRoot 'ModelChecks.java')
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed.' }
& java "-Dnetlogo.extensions.dir=$NetLogoHome/extensions" -cp "$buildDirectory;$classpath" ModelChecks (Join-Path $PSScriptRoot '../MobileBankMarkets.nlogox')
if ($LASTEXITCODE -ne 0) { throw 'Model checks failed.' }
& javac -cp $classpath -d $buildDirectory (Join-Path $PSScriptRoot 'PortableChecks.java')
if ($LASTEXITCODE -ne 0) { throw 'Portable check compilation failed.' }
& java "-Dnetlogo.extensions.dir=$NetLogoHome/extensions" -cp "$buildDirectory;$classpath" PortableChecks (Join-Path $PSScriptRoot '../MobileBankMarkets.nlogox')
if ($LASTEXITCODE -ne 0) { throw 'Portable model checks failed.' }
