import "@testing-library/react-native/extend-expect";

declare global {
  namespace jest {
    interface Matchers<R> {
      toBeOnTheScreen(): R;
    }
  }
}
