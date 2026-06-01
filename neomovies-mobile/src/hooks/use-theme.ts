/**
 * Learn more about light and dark modes:
 * https://docs.expo.dev/guides/color-schemes/
 */

import { Colors } from '@/constants/theme';
import { useAppTheme } from '@/hooks/use-app-theme';

export function useTheme() {
  const { resolvedTheme } = useAppTheme();
  return Colors[resolvedTheme];
}
