import { Pressable, StyleSheet, ActivityIndicator } from "react-native";
import { tokens } from "../theme/tokens";
import { Text } from "./Text";

export function Button({
  title, onPress, loading, disabled, testID,
}: {
  title: string; onPress: () => void; loading?: boolean; disabled?: boolean; testID?: string;
}) {
  return (
    <Pressable
      testID={testID}
      onPress={onPress}
      disabled={disabled || loading}
      style={[styles.btn, (disabled || loading) && styles.disabled]}
    >
      {loading ? (
        <ActivityIndicator color={tokens.color.primaryText} />
      ) : (
        <Text style={styles.label}>{title}</Text>
      )}
    </Pressable>
  );
}
const styles = StyleSheet.create({
  btn: {
    backgroundColor: tokens.color.primary, borderRadius: tokens.radius.md,
    paddingVertical: tokens.space.md, alignItems: "center",
  },
  disabled: { opacity: 0.5 },
  label: { color: tokens.color.primaryText, fontSize: tokens.font.md, fontWeight: "600" },
});
