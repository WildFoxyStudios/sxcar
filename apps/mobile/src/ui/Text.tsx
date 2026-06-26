import { Text as RNText, TextProps, StyleSheet } from "react-native";
import { tokens } from "../theme/tokens";

export function Text({ style, ...props }: TextProps) {
  return <RNText style={[styles.base, style]} {...props} />;
}
const styles = StyleSheet.create({
  base: { color: tokens.color.text, fontSize: tokens.font.md },
});
