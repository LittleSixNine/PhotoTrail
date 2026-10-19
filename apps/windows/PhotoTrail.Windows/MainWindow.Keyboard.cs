using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    // Popup items have a separate visual root. Inspect the owning window's controls,
    // so Escape belongs to its open picker before any task or window action.
    static bool CloseOpenDropdown(DependencyObject root)
    {
        if (root is ComboBox { IsDropDownOpen: true } picker)
        {
            picker.IsDropDownOpen = false;
            picker.Focus();
            return true;
        }
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            if (CloseOpenDropdown(VisualTreeHelper.GetChild(root, i))) return true;
        return false;
    }

    void ReturnEditorFocus(IInputElement? previous)
    {
        Activate();
        if (previous is UIElement { IsVisible: true, IsEnabled: true } element) element.Focus();
    }
}
