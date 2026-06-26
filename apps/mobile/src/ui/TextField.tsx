import { TextInput, StyleSheet, View, TextInputProps } from "react-native";
import { tokens } from "../theme/tokens";
import { Text } from "./Text";

export function TextField({ label, ...props }: { label: string } & TextInputProps) {
  return (
    <View style={styles.wrap}>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        style={styles.input}
        placeholderTextColor={tokens.color.textMuted}
        {...props}
      />
    </View>
  );
}
const styles = StyleSheet.create({
  wrap: { gap: tokens.space.xs },
  label: { color: tokens.color.textMuted, fontSize: tokens.font.sm },
  input: {
    backgroundColor: tokens.color.surface, color: tokens.color.text,
    borderWidth: 1, borderColor: tokens.color.border, borderRadius: tokens.radius.sm,
    paddingHorizontal: tokens.space.md, paddingVertical: tokens.space.sm, fontSize: tokens.font.md,
  },
});
