import { render, screen, fireEvent } from "@testing-library/react-native";
import { Button } from "../src/ui/Button";

test("Button renders title and fires onPress", () => {
  const onPress = jest.fn();
  render(<Button title="Entrar" onPress={onPress} testID="btn" />);
  expect(screen.getByText("Entrar")).toBeOnTheScreen();
  fireEvent.press(screen.getByTestId("btn"));
  expect(onPress).toHaveBeenCalledTimes(1);
});
