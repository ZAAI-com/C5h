import { useState } from "react";
import { useStore } from "@/store";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/shadcn-ui/card";
import { Button } from "@/components/shadcn-ui/button";
import { Input } from "@/components/shadcn-ui/input";
import { Label } from "@/components/shadcn-ui/label";
import { Switch } from "@/components/shadcn-ui/switch";
import { Separator } from "@/components/shadcn-ui/separator";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/shadcn-ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/shadcn-ui/dialog";
import { Settings, Bell, Palette, Plus, Pencil, Trash2 } from "lucide-react";
import type { Account, NewAccount } from "@/lib/types";

const TOOL_TYPES = ["claude", "codex", "gemini"];
const THEME_OPTIONS = ["system", "light", "dark"];
const COLORS = [
  "#6366f1", // Indigo
  "#10a37f", // Green
  "#4285f4", // Blue
  "#f59e0b", // Amber
  "#ef4444", // Red
  "#8b5cf6", // Purple
  "#06b6d4", // Cyan
  "#ec4899", // Pink
];

export function SettingsView() {
  const settings = useStore((state) => state.settings);
  const accounts = useStore((state) => state.accounts);
  const saveSettings = useStore((state) => state.saveSettings);
  const createAccount = useStore((state) => state.createAccount);
  const updateAccount = useStore((state) => state.updateAccount);
  const deleteAccount = useStore((state) => state.deleteAccount);

  const [isAccountDialogOpen, setIsAccountDialogOpen] = useState(false);
  const [editingAccount, setEditingAccount] = useState<Account | null>(null);
  const [accountForm, setAccountForm] = useState<NewAccount>({
    name: "",
    tool_type: "claude",
    cli_command: "claude",
    cli_args: "",
    window_duration_hours: 5,
    color: COLORS[0],
    enabled: true,
  });

  const handleSettingChange = (
    key: keyof NonNullable<typeof settings>,
    value: boolean | string | number
  ) => {
    if (settings) {
      saveSettings({ ...settings, [key]: value });
    }
  };

  const handleOpenAccountDialog = (account?: Account) => {
    if (account) {
      setEditingAccount(account);
      setAccountForm({
        name: account.name,
        tool_type: account.tool_type,
        cli_command: account.cli_command,
        cli_args: account.cli_args,
        window_duration_hours: account.window_duration_hours,
        color: account.color,
        enabled: account.enabled,
      });
    } else {
      setEditingAccount(null);
      setAccountForm({
        name: "",
        tool_type: "claude",
        cli_command: "claude",
        cli_args: "",
        window_duration_hours: 5,
        color: COLORS[accounts.length % COLORS.length],
        enabled: true,
      });
    }
    setIsAccountDialogOpen(true);
  };

  const handleSaveAccount = async () => {
    if (editingAccount?.id) {
      await updateAccount({ ...editingAccount, ...accountForm });
    } else {
      await createAccount(accountForm);
    }
    setIsAccountDialogOpen(false);
  };

  const handleDeleteAccount = async (id: number) => {
    if (confirm("Are you sure you want to delete this account?")) {
      await deleteAccount(id);
    }
  };

  if (!settings) {
    return <div>Loading settings...</div>;
  }

  return (
    <div className="space-y-6 max-w-2xl">
      {/* General Settings */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Settings className="h-5 w-5" />
            General
          </CardTitle>
          <CardDescription>Configure app behavior</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="launch_at_login">Launch at Login</Label>
              <p className="text-sm text-muted-foreground">
                Start C5h automatically when you log in
              </p>
            </div>
            <Switch
              id="launch_at_login"
              checked={settings.launch_at_login}
              onCheckedChange={(checked) =>
                handleSettingChange("launch_at_login", checked)
              }
            />
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="show_in_menu_bar">Show in Menu Bar</Label>
              <p className="text-sm text-muted-foreground">
                Display status icon in the menu bar
              </p>
            </div>
            <Switch
              id="show_in_menu_bar"
              checked={settings.show_in_menu_bar}
              onCheckedChange={(checked) =>
                handleSettingChange("show_in_menu_bar", checked)
              }
            />
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="poll_interval">Poll Interval</Label>
              <p className="text-sm text-muted-foreground">
                How often to check for CLI activity (minutes)
              </p>
            </div>
            <Select
              value={String(settings.poll_interval_minutes)}
              onValueChange={(value) =>
                handleSettingChange("poll_interval_minutes", parseInt(value))
              }
            >
              <SelectTrigger className="w-24">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="5">5</SelectItem>
                <SelectItem value="10">10</SelectItem>
                <SelectItem value="15">15</SelectItem>
                <SelectItem value="30">30</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>

      {/* Appearance */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Palette className="h-5 w-5" />
            Appearance
          </CardTitle>
          <CardDescription>Customize the look and feel</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="theme">Theme</Label>
              <p className="text-sm text-muted-foreground">
                Choose your preferred color scheme
              </p>
            </div>
            <Select
              value={settings.theme}
              onValueChange={(value) => handleSettingChange("theme", value)}
            >
              <SelectTrigger className="w-32">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {THEME_OPTIONS.map((theme) => (
                  <SelectItem key={theme} value={theme}>
                    {theme.charAt(0).toUpperCase() + theme.slice(1)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>

      {/* Notifications */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Bell className="h-5 w-5" />
            Notifications
          </CardTitle>
          <CardDescription>Configure alerts and reminders</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="notifications_enabled">Enable Notifications</Label>
              <p className="text-sm text-muted-foreground">
                Show system notifications
              </p>
            </div>
            <Switch
              id="notifications_enabled"
              checked={settings.notifications_enabled}
              onCheckedChange={(checked) =>
                handleSettingChange("notifications_enabled", checked)
              }
            />
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="notify_ending_soon">Window Ending Soon</Label>
              <p className="text-sm text-muted-foreground">
                Alert when window is about to expire
              </p>
            </div>
            <Switch
              id="notify_ending_soon"
              checked={settings.notify_ending_soon}
              disabled={!settings.notifications_enabled}
              onCheckedChange={(checked) =>
                handleSettingChange("notify_ending_soon", checked)
              }
            />
          </div>

          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="notify_trigger_status">Trigger Status</Label>
              <p className="text-sm text-muted-foreground">
                Notify about scheduled trigger results
              </p>
            </div>
            <Switch
              id="notify_trigger_status"
              checked={settings.notify_trigger_status}
              disabled={!settings.notifications_enabled}
              onCheckedChange={(checked) =>
                handleSettingChange("notify_trigger_status", checked)
              }
            />
          </div>

          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="notify_weekly_summary">Weekly Summary</Label>
              <p className="text-sm text-muted-foreground">
                Send a weekly usage summary
              </p>
            </div>
            <Switch
              id="notify_weekly_summary"
              checked={settings.notify_weekly_summary}
              disabled={!settings.notifications_enabled}
              onCheckedChange={(checked) =>
                handleSettingChange("notify_weekly_summary", checked)
              }
            />
          </div>
        </CardContent>
      </Card>

      {/* Accounts */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Accounts</CardTitle>
              <CardDescription>Manage your AI tool accounts</CardDescription>
            </div>
            <Dialog open={isAccountDialogOpen} onOpenChange={setIsAccountDialogOpen}>
              <DialogTrigger asChild>
                <Button onClick={() => handleOpenAccountDialog()}>
                  <Plus className="h-4 w-4 mr-2" />
                  Add Account
                </Button>
              </DialogTrigger>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>
                    {editingAccount ? "Edit Account" : "Add Account"}
                  </DialogTitle>
                  <DialogDescription>
                    Configure an AI tool account for tracking.
                  </DialogDescription>
                </DialogHeader>

                <div className="space-y-4 py-4">
                  <div className="space-y-2">
                    <Label htmlFor="name">Name</Label>
                    <Input
                      id="name"
                      value={accountForm.name}
                      onChange={(e) =>
                        setAccountForm({ ...accountForm, name: e.target.value })
                      }
                      placeholder="Claude Code"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="tool_type">Tool Type</Label>
                    <Select
                      value={accountForm.tool_type}
                      onValueChange={(value) =>
                        setAccountForm({ ...accountForm, tool_type: value })
                      }
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {TOOL_TYPES.map((type) => (
                          <SelectItem key={type} value={type}>
                            {type.charAt(0).toUpperCase() + type.slice(1)}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="cli_command">CLI Command</Label>
                    <Input
                      id="cli_command"
                      value={accountForm.cli_command}
                      onChange={(e) =>
                        setAccountForm({
                          ...accountForm,
                          cli_command: e.target.value,
                        })
                      }
                      placeholder="claude"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="window_duration">Window Duration (hours)</Label>
                    <Input
                      id="window_duration"
                      type="number"
                      min={1}
                      max={24}
                      value={accountForm.window_duration_hours}
                      onChange={(e) =>
                        setAccountForm({
                          ...accountForm,
                          window_duration_hours: parseInt(e.target.value) || 5,
                        })
                      }
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Color</Label>
                    <div className="flex gap-2 flex-wrap">
                      {COLORS.map((color) => (
                        <button
                          key={color}
                          type="button"
                          className={`w-8 h-8 rounded-full border-2 ${
                            accountForm.color === color
                              ? "border-foreground"
                              : "border-transparent"
                          }`}
                          style={{ backgroundColor: color }}
                          onClick={() =>
                            setAccountForm({ ...accountForm, color })
                          }
                        />
                      ))}
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <Switch
                      id="enabled"
                      checked={accountForm.enabled}
                      onCheckedChange={(checked) =>
                        setAccountForm({ ...accountForm, enabled: checked })
                      }
                    />
                    <Label htmlFor="enabled">Enabled</Label>
                  </div>
                </div>

                <DialogFooter>
                  <Button
                    variant="outline"
                    onClick={() => setIsAccountDialogOpen(false)}
                  >
                    Cancel
                  </Button>
                  <Button onClick={handleSaveAccount}>Save</Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>
        </CardHeader>
        <CardContent>
          {accounts.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No accounts configured. Add one to get started.
            </p>
          ) : (
            <div className="space-y-2">
              {accounts.map((account) => (
                <div
                  key={account.id}
                  className="flex items-center justify-between p-3 rounded-lg bg-muted"
                >
                  <div className="flex items-center gap-3">
                    <div
                      className="w-4 h-4 rounded-full"
                      style={{ backgroundColor: account.color }}
                    />
                    <div>
                      <p className="font-medium">{account.name}</p>
                      <p className="text-sm text-muted-foreground">
                        {account.cli_command} · {account.window_duration_hours}h
                        window
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {!account.enabled && (
                      <span className="text-xs text-yellow-600">Disabled</span>
                    )}
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleOpenAccountDialog(account)}
                    >
                      <Pencil className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => account.id && handleDeleteAccount(account.id)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
