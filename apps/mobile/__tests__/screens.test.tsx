jest.mock("../src/auth/storage", () => {
  let mem: any = null;
  return {
    getTokens: async () => mem,
    setTokens: async (t: any) => {
      mem = t;
    },
    clearTokens: async () => {
      mem = null;
    },
  };
});

jest.mock("expo-router", () => ({
  useRouter: () => ({ replace: jest.fn() }),
  Link: ({ children }: any) => children,
  useSegments: () => [],
}));

jest.mock("../src/api/auth", () => ({
  auth: {
    login: jest.fn(async () => ({ access: "a", refresh: "r" })),
    register: jest.fn(async () => ({ access: "a", refresh: "r" })),
    verifyEmail: jest.fn(async () => ({ ok: true })),
    resendEmail: jest.fn(async () => ({})),
    logout: jest.fn(async () => ({})),
  },
}));

import { render, screen, fireEvent, waitFor } from "@testing-library/react-native";
import Login from "../src/app/(auth)/login";
import Register from "../src/app/(auth)/register";
import { auth } from "../src/api/auth";

test("login submits and calls auth.login", async () => {
  render(<Login />);
  const inputs = screen.getAllByDisplayValue("");
  fireEvent.changeText(inputs[0], "a@b.com");
  fireEvent.press(screen.getByTestId("login-submit"));
  await waitFor(() => expect(auth.login).toHaveBeenCalled());
});

test("register under-18 does not submit", async () => {
  render(<Register />);
  fireEvent.press(screen.getByTestId("register-submit"));
  expect(auth.register).not.toHaveBeenCalled();
  expect(screen.getByText(/18 años/)).toBeOnTheScreen();
});
