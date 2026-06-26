import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import Home from "@/app/page";

// Mock next/link to avoid issues with Next runtime in tests
vi.mock("next/link", () => {
  return {
    default: ({ href, children, ...props }: { href: string; children: ReactNode; [key: string]: unknown }) => (
      <a href={href} {...props}>
        {children}
      </a>
    ),
  };
});

describe("landing", () => {
  it("renders the hero tagline and store CTAs", () => {
    render(<Home />);
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
    expect(screen.getByText("App Store")).toBeTruthy();
    expect(screen.getByText("Google Play")).toBeTruthy();
  });
});
