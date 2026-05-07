import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { Layout } from "./Layout";

describe("Layout", () => {
  it("adds stable accessible names to tab triggers", () => {
    render(
      <Layout
        activeTab="calendar"
        calendarContent={<div>Calendar Content</div>}
        statsContent={<div>Stats Content</div>}
        settingsContent={<div>Settings Content</div>}
      />
    );

    expect(screen.getByRole("tab", { name: "Calendar" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Stats" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Settings" })).toBeInTheDocument();
  });
});
