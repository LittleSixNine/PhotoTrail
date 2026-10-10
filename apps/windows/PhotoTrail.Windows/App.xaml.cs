using System.Windows;

namespace PhotoTrail.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        // Table/form UI uses software rendering to remain visible in remote/capture sessions.
        System.Windows.Media.RenderOptions.ProcessRenderMode = System.Windows.Interop.RenderMode.SoftwareOnly;
        base.OnStartup(e);
    }
}
