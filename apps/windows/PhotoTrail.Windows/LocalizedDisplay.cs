using System.Globalization;
using System.Windows.Data;

namespace PhotoTrail.Windows;

// Applied only to generated statuses/reasons, never to file names, metadata values or editable inputs.
public sealed class LocalizedDisplay:IValueConverter
{
    public object Convert(object value,Type targetType,object parameter,CultureInfo culture)=>L10n.Message(value?.ToString()??"");
    public object ConvertBack(object value,Type targetType,object parameter,CultureInfo culture)=>Binding.DoNothing;
}
