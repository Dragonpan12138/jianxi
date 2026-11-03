Add-Type -AssemblyName System.Drawing

$assetPath = Join-Path $PSScriptRoot '../Jianxi/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png'
$bitmap = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$light = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#D8F0E3'))
$dark = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#276B53'))

try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.ScaleTransform(1024.0 / 108.0, 1024.0 / 108.0)
    $graphics.FillRectangle($light, 0, 0, 108, 108)

    $body = [System.Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $body.AddArc(24, 22, 14, 14, 180, 90)
        $body.AddArc(70, 22, 14, 14, 270, 90)
        $body.AddArc(70, 72, 14, 14, 0, 90)
        $body.AddArc(24, 72, 14, 14, 90, 90)
        $body.CloseFigure()
        $graphics.FillPath($dark, $body)
    } finally {
        $body.Dispose()
    }

    $graphics.FillRectangle($light, 33, 31, 5, 5)
    $graphics.FillRectangle($light, 43, 31, 5, 5)
    $graphics.FillEllipse($light, 36, 42, 36, 36)

    $wave = [System.Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $wave.AddBezier(41, 59, 45, 65, 50, 65, 54, 59)
        $wave.AddBezier(54, 59, 58, 53, 63, 53, 67, 59)
        $wave.AddArc(41, 46, 26, 26, 0, 180)
        $wave.CloseFigure()
        $graphics.FillPath($dark, $wave)
    } finally {
        $wave.Dispose()
    }

    $bitmap.Save($assetPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $dark.Dispose()
    $light.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}
