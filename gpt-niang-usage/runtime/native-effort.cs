
using System;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Automation;

public sealed class GptNiangNativeEffort : IDisposable
{
    public sealed class Sample {
        public readonly long Host, At;
        public readonly string Stage, Source;
        public Sample(long host, string stage, string source) {
            Host = host; Stage = stage; Source = source;
            At = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        }
    }

    static readonly PropertyCondition MenuType = new PropertyCondition(
        AutomationElement.ControlTypeProperty, ControlType.Menu);
    static readonly PropertyCondition SliderType = new PropertyCondition(
        AutomationElement.ControlTypeProperty, ControlType.Slider);
    static readonly PropertyCondition ButtonType = new PropertyCondition(
        AutomationElement.ControlTypeProperty, ControlType.Button);
    static readonly Condition MenuSelector = new AndCondition(MenuType, new OrCondition(
        new PropertyCondition(AutomationElement.NameProperty, "\u9009\u62e9\u63a8\u7406\u5f3a\u5ea6"),
        new PropertyCondition(AutomationElement.NameProperty, "Select effort"),
        new PropertyCondition(AutomationElement.NameProperty, "Select reasoning effort")));
    static readonly Regex Composer = new Regex(
        @"^GPT[- ]6(?:\.[0-9]+)?[- ](?:Luna|Sol|Astra|Terra)\s+(?<stage>.+)$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    static readonly string[] StageOrder = {"low", "medium", "high", "xhigh", "max", "max"};

    readonly AutoResetEvent wake = new AutoResetEvent(false);
    readonly Thread thread;
    long host;
    int stopped;
    Sample sample;
    AutomationElement window, menu, slider, button;
    long currentHost;
    DateTime nextMenuSearch = DateTime.MinValue;
    DateTime nextButtonSearch = DateTime.MinValue;

    public GptNiangNativeEffort() {
        thread = new Thread(Work) { IsBackground = true, Name = "GPT Niang reasoning readout" };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
    }

    public void SetHost(long value) {
        if (Interlocked.Exchange(ref host, value) != value) wake.Set();
    }

    public Sample Read(long expectedHost) {
        Sample current = Volatile.Read(ref sample);
        if (current == null || expectedHost != current.Host) return null;
        long age = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - current.At;
        return age >= 0 && age < 900 ? current : null;
    }

    static bool Visible(AutomationElement element) {
        if (element == null) return false;
        try { return !element.Current.IsOffscreen; }
        catch (ElementNotAvailableException) { return false; }
    }

    static string FromLabel(string label) {
        if (label == null) return null;
        switch (label.Trim().ToLowerInvariant()) {
            case "\u8f7b": case "\u8f7b\u5ea6": case "\u4f4e": case "low": case "light": return "low";
            case "\u4e2d": case "\u4e2d\u5ea6": case "\u4e2d\u7b49": case "medium": return "medium";
            case "\u9ad8": case "\u9ad8\u5ea6": case "high": return "high";
            case "\u6781\u9ad8": case "\u8d85\u9ad8": case "extra high": case "xhigh": return "xhigh";
            case "ultra": case "maximum": case "max": return "max";
            default: return null;
        }
    }

    static string ReadSlider(AutomationElement element) {
        if (!Visible(element)) return null;
        object pattern;
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out pattern)) {
            string label = FromLabel(((ValuePattern)pattern).Current.Value);
            if (label != null) return label;
        }
        if (!element.TryGetCurrentPattern(RangeValuePattern.Pattern, out pattern)) return null;
        var range = ((RangeValuePattern)pattern).Current;
        double value = range.Value;
        if (double.IsNaN(value) || range.Minimum != 0 || range.Maximum < 3 ||
            range.Maximum > 5 || value < 0 || value > range.Maximum || value != Math.Truncate(value))
            return null;
        // The observed desktop slider starts at Low and indexes the available ordered stages.
        // Max and Ultra use the same final form.
        return StageOrder[(int)value];
    }

    static string ReadComposer(AutomationElement element) {
        if (!Visible(element)) return null;
        Match match = Composer.Match(element.Current.Name ?? "");
        object pattern;
        if (!match.Success || !element.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out pattern))
            return null;
        return FromLabel(match.Groups["stage"].Value);
    }

    Sample Scan(long target) {
        if (target != currentHost) {
            currentHost = target;
            window = menu = slider = button = null;
            nextMenuSearch = nextButtonSearch = DateTime.MinValue;
        }
        if (target == 0) return null;
        if (window == null) window = AutomationElement.FromHandle(new IntPtr(target));
        DateTime now = DateTime.UtcNow;
        if (!Visible(menu)) {
            menu = slider = null;
            if (now >= nextMenuSearch) {
                nextMenuSearch = now.AddMilliseconds(100);
                menu = window.FindFirst(TreeScope.Descendants, MenuSelector);
            }
        }
        if (Visible(menu)) {
            if (!Visible(slider)) slider = menu.FindFirst(TreeScope.Descendants, SliderType);
            string value = ReadSlider(slider);
            return value == null ? null : new Sample(target, value, "native-slider");
        }

        string stage = ReadComposer(button);
        if (stage != null) return new Sample(target, stage, "native-composer");
        button = null;
        if (now < nextButtonSearch) return null;
        nextButtonSearch = now.AddMilliseconds(350);
        foreach (AutomationElement element in window.FindAll(TreeScope.Descendants, ButtonType)) {
            stage = ReadComposer(element);
            if (stage == null) continue;
            // An ambiguous composer selection is safer to leave to the session-log fallback.
            if (button != null) { button = null; return null; }
            button = element;
        }
        stage = ReadComposer(button);
        return stage == null ? null : new Sample(target, stage, "native-composer");
    }

    void Work() {
        try {
            while (Volatile.Read(ref stopped) == 0) {
                long target = Interlocked.Read(ref host);
                Sample next = null;
                try { next = Scan(target); }
                catch (Exception) { window = menu = slider = button = null; }
                // Keep a fresh sample through a brief remount of the picker.
                // Read() rejects the previous window and expires old values.
                if (target == Interlocked.Read(ref host) && (next != null || target == 0))
                    Volatile.Write(ref sample, next);
                wake.WaitOne(next != null && next.Source == "native-slider" ? 35 : 85);
            }
        }
        finally { wake.Dispose(); }
    }

    public void Dispose() {
        if (Interlocked.Exchange(ref stopped, 1) == 0) {
            try { wake.Set(); } catch (ObjectDisposedException) { }
        }
    }
}
