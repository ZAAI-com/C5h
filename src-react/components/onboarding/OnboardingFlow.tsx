import { useState } from "react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
import { Button } from "@/components/shadcn-ui/button";
import { Input } from "@/components/shadcn-ui/input";
import { Label } from "@/components/shadcn-ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/shadcn-ui/select";
import { Sparkles, ArrowRight, Check, Wand2, Keyboard } from "lucide-react";
import { useStore } from "@/store";
import {
  checkCliAvailability,
  markOnboardingCompleted,
  type NewAccount,
} from "@/lib/api";

interface Props {
  onComplete: () => void;
}

const TOOL_PRESETS: Array<{
  tool_type: string;
  label: string;
  cli: string;
  args: string;
  durationHours: number;
  color: string;
}> = [
  { tool_type: "claude", label: "Claude Code", cli: "claude", args: '-p "1+1"', durationHours: 5, color: "#6366f1" },
  { tool_type: "codex", label: "Codex", cli: "codex", args: '-p "1+1"', durationHours: 5, color: "#10a37f" },
  { tool_type: "gemini", label: "Gemini", cli: "gemini", args: "", durationHours: 24, color: "#4285f4" },
];

type Step = "welcome" | "account" | "menubar";

/**
 * First-run onboarding flow.
 *
 * Three steps, sub-60s when defaults are accepted:
 *   1. Welcome — what the app does and what permissions it needs.
 *   2. Account — pick a tool, prefilled CLI command + args, live availability check.
 *   3. Menu bar intro — point at the tray icon and explain Cmd+Shift+5.
 *
 * Completion is persisted server-side so closing the app mid-flow re-opens it.
 */
export function OnboardingFlow({ onComplete }: Props) {
  const [step, setStep] = useState<Step>("welcome");
  const [preset, setPreset] = useState(TOOL_PRESETS[0]);
  const [name, setName] = useState("Claude Code");
  const [checking, setChecking] = useState(false);
  const [cliPath, setCliPath] = useState<string | null>(null);
  const [cliError, setCliError] = useState<string | null>(null);
  const createAccount = useStore((s) => s.createAccount);

  const handleSelectPreset = (toolType: string) => {
    const next = TOOL_PRESETS.find((p) => p.tool_type === toolType) ?? TOOL_PRESETS[0];
    setPreset(next);
    setName(next.label);
    setCliPath(null);
    setCliError(null);
  };

  const runCliCheck = async () => {
    setChecking(true);
    setCliError(null);
    try {
      const path = await checkCliAvailability(preset.cli);
      setCliPath(path);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setCliError(msg);
      setCliPath(null);
    } finally {
      setChecking(false);
    }
  };

  const handleCreateAccount = async () => {
    const payload: NewAccount = {
      name: name.trim() || preset.label,
      tool_type: preset.tool_type,
      cli_command: preset.cli,
      cli_args: preset.args || undefined,
      window_duration_hours: preset.durationHours,
      color: preset.color,
      enabled: true,
    };
    try {
      await createAccount(payload);
      setStep("menubar");
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      toast.error(`Could not create account: ${msg}`);
    }
  };

  const finish = async () => {
    try {
      await markOnboardingCompleted();
    } catch (err) {
      // Non-blocking: even if persistence fails the user can dismiss the flow.
      console.error("Failed to persist onboarding completion", err);
    }
    onComplete();
  };

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-6">
      <Card className="w-full max-w-xl">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-primary" />
            Welcome to C5h
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          {step === "welcome" && (
            <>
              <p className="text-sm text-muted-foreground">
                C5h tracks your AI coding tool usage windows, so you always know
                how much time is left before the next reset — and can schedule
                window starts at night to avoid wasting your work-hour budget.
              </p>
              <div className="rounded-md border bg-muted/30 p-4 text-sm space-y-2">
                <p className="font-medium">What this needs from macOS:</p>
                <ul className="list-disc list-inside space-y-1 text-muted-foreground">
                  <li>Permission to run your CLI tools (you'll grant this on first poll).</li>
                  <li>Notifications, so we can warn you when a window is ending.</li>
                  <li>Optional: launchd access for scheduled wake-up triggers.</li>
                </ul>
              </div>
              <div className="flex justify-end">
                <Button onClick={() => setStep("account")}>
                  Get started
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Button>
              </div>
            </>
          )}

          {step === "account" && (
            <>
              <p className="text-sm text-muted-foreground">
                Add your first AI tool. We've prefilled the defaults for each —
                you can tweak anything later in Settings.
              </p>
              <div className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="onboarding-tool">Tool</Label>
                  <Select value={preset.tool_type} onValueChange={handleSelectPreset}>
                    <SelectTrigger id="onboarding-tool">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {TOOL_PRESETS.map((p) => (
                        <SelectItem key={p.tool_type} value={p.tool_type}>
                          {p.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="onboarding-name">Account name</Label>
                  <Input
                    id="onboarding-name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder={preset.label}
                  />
                </div>
                <div className="space-y-2">
                  <Label>CLI command</Label>
                  <div className="flex items-center gap-2">
                    <code className="px-2 py-1 rounded bg-muted text-xs">{preset.cli}</code>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={runCliCheck}
                      disabled={checking}
                    >
                      <Wand2 className="mr-2 h-4 w-4" />
                      {checking ? "Checking…" : "Verify"}
                    </Button>
                  </div>
                  {cliPath && (
                    <p className="text-xs text-green-600 flex items-center gap-1">
                      <Check className="h-3 w-3" />
                      Found at {cliPath}
                    </p>
                  )}
                  {cliError && (
                    <p className="text-xs text-destructive">{cliError}</p>
                  )}
                </div>
              </div>
              <div className="flex justify-between">
                <Button variant="ghost" onClick={() => setStep("welcome")}>
                  Back
                </Button>
                <Button onClick={handleCreateAccount}>
                  Create and continue
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Button>
              </div>
            </>
          )}

          {step === "menubar" && (
            <>
              <div className="space-y-3">
                <p className="text-sm">You're all set!</p>
                <div className="rounded-md border bg-muted/30 p-4 text-sm space-y-2">
                  <p className="font-medium flex items-center gap-2">
                    <Keyboard className="h-4 w-4" />
                    Two ways to open C5h
                  </p>
                  <ul className="list-disc list-inside space-y-1 text-muted-foreground">
                    <li>Click the C5h icon in your macOS menu bar.</li>
                    <li>
                      Press <kbd className="px-1 py-0.5 text-xs rounded bg-muted">⌘ + ⇧ + 5</kbd>{" "}
                      from any app — it's a global shortcut.
                    </li>
                  </ul>
                </div>
                <p className="text-sm text-muted-foreground">
                  Window detection runs in the background. You'll see your first
                  window appear on the calendar as soon as you use the CLI.
                </p>
              </div>
              <div className="flex justify-end">
                <Button onClick={finish}>
                  <Check className="mr-2 h-4 w-4" />
                  Finish
                </Button>
              </div>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
