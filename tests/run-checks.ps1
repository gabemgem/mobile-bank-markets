param([string]$NetLogoHome = 'C:/Program Files/NetLogo 7.0.3', [switch]$FullLibrary)
$ErrorActionPreference = 'Stop'
$buildDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('mobile-money-checks-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $buildDirectory | Out-Null
$classpath = Join-Path $NetLogoHome 'app/*'
& javac -cp $classpath -d $buildDirectory (Join-Path $PSScriptRoot 'ModelChecks.java') (Join-Path $PSScriptRoot 'PortableChecks.java') (Join-Path $PSScriptRoot 'WebNetworkChecks.java') (Join-Path $PSScriptRoot 'V2Checks.java') (Join-Path $PSScriptRoot 'SpatialCommissionChecks.java') (Join-Path $PSScriptRoot 'SyntheticLibraryChecks.java')
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed.' }
& java "-Dnetlogo.extensions.dir=$NetLogoHome/extensions" -cp "$buildDirectory;$classpath" ModelChecks (Join-Path $PSScriptRoot '../MobileBankMarkets_v1.nlogox')
if ($LASTEXITCODE -ne 0) { throw 'Model checks failed.' }
foreach ($version in @('v1','v2')) {
    $modelPath = Join-Path $PSScriptRoot "../MobileBankMarkets_$version.nlogox"
    foreach ($check in @('PortableChecks','WebNetworkChecks')) {
        & java "-Dnetlogo.extensions.dir=$NetLogoHome/extensions" -cp "$buildDirectory;$classpath" $check $modelPath
        if ($LASTEXITCODE -ne 0) { throw "$check failed for $version." }
    }
    if ($FullLibrary) {
        & java "-Dnetlogo.extensions.dir=$NetLogoHome/extensions" -cp "$buildDirectory;$classpath" SyntheticLibraryChecks $modelPath
        if ($LASTEXITCODE -ne 0) { throw "Synthetic library checks failed for $version." }
    }
}
& java "-Dnetlogo.extensions.dir=$NetLogoHome/extensions" -cp "$buildDirectory;$classpath" V2Checks (Join-Path $PSScriptRoot '../MobileBankMarkets_v1.nlogox') (Join-Path $PSScriptRoot '../MobileBankMarkets_v2.nlogox')
if ($LASTEXITCODE -ne 0) { throw 'V2 mechanism checks failed.' }
& java "-Dnetlogo.extensions.dir=$NetLogoHome/extensions" -cp "$buildDirectory;$classpath" SpatialCommissionChecks (Join-Path $PSScriptRoot '../MobileBankMarkets_v1.nlogox') (Join-Path $PSScriptRoot '../MobileBankMarkets_v2.nlogox')
if ($LASTEXITCODE -ne 0) { throw 'Spatial commission checks failed.' }
