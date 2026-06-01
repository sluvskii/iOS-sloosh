import React, { ReactNode } from 'react';
import { Pressable, View } from 'react-native';
import { Check } from 'lucide-react-native';

import { useTheme } from '@/hooks/use-theme';
import { ThemedText } from '@/components/themed-text';
import { createSelectionItemStyles } from '@/styles/selection-item.styles';

type SelectionItemProps = {
  title: string;
  subtitle?: string;
  selected?: boolean;
  disabled?: boolean;
  onPress: () => void;
  leftAccessory?: ReactNode;
};

export function SelectionItem({
  title,
  subtitle,
  selected = false,
  disabled = false,
  onPress,
  leftAccessory,
}: SelectionItemProps) {
  const theme = useTheme();
  const styles = createSelectionItemStyles(theme);

  return (
    <Pressable
      style={({ pressed }) => [
        styles.item,
        selected ? styles.itemSelected : null,
        disabled ? styles.itemDisabled : null,
        pressed && !disabled ? styles.itemPressed : null,
      ]}
      onPress={onPress}
      disabled={disabled}
    >
      <View style={styles.left}>
        {leftAccessory ? <View style={styles.leftAccessory}>{leftAccessory}</View> : null}
        <View style={styles.textWrap}>
          <ThemedText style={[styles.title, disabled ? styles.titleDisabled : null]}>{title}</ThemedText>
          {subtitle ? (
            <ThemedText style={styles.subtitle} themeColor="textSecondary">
              {subtitle}
            </ThemedText>
          ) : null}
        </View>
      </View>
      {selected ? <Check size={22} color={theme.accent} strokeWidth={2.5} /> : null}
    </Pressable>
  );
}
