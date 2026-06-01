import { ReactNode } from 'react';
import { Pressable, View } from 'react-native';
import { ChevronRight } from 'lucide-react-native';

import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';
import { createListRowItemStyles } from '@/styles/list-row-item.styles';

type ListRowItemProps = {
  title: string;
  subtitle?: string;
  value?: string;
  onPress?: () => void;
  leftAccessory?: ReactNode;
  rightAccessory?: ReactNode;
  showChevron?: boolean;
  disabled?: boolean;
};

export function ListRowItem({
  title,
  subtitle,
  value,
  onPress,
  leftAccessory,
  rightAccessory,
  showChevron = false,
  disabled = false,
}: ListRowItemProps) {
  const theme = useTheme();
  const styles = createListRowItemStyles(theme);
  const Content = (
    <>
      <View style={styles.left}>
        {leftAccessory}
        <View style={styles.textWrap}>
          <ThemedText style={styles.title}>{title}</ThemedText>
          {subtitle ? <ThemedText style={styles.subtitle}>{subtitle}</ThemedText> : null}
        </View>
      </View>
      <View style={styles.right}>
        {value ? <ThemedText style={styles.value}>{value}</ThemedText> : null}
        {rightAccessory}
        {showChevron ? <ChevronRight size={18} color={theme.textMuted} /> : null}
      </View>
    </>
  );

  if (!onPress) {
    return <View style={styles.row}>{Content}</View>;
  }

  return (
    <Pressable
      style={({ pressed }) => [styles.row, pressed && !disabled ? styles.pressed : null]}
      onPress={onPress}
      disabled={disabled}
    >
      {Content}
    </Pressable>
  );
}
