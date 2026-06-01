import React, { PropsWithChildren } from 'react';
import { TamaguiProvider } from 'tamagui';

import config from '../../tamagui.config';

export function AppTamaguiProvider({ children }: PropsWithChildren) {
  return (
    <TamaguiProvider config={config} defaultTheme="dark">
      {children}
    </TamaguiProvider>
  );
}
