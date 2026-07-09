import { Box, Button, NoticeBox, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type VaultLace = {
  index: number;
  name: string;
  faction: string | null;
  damage: number;
  occupied: BooleanLike;
  was_occupied: BooleanLike;
};

export type LaceVaultData = {
  network: string;
  capacity: number;
  laces: VaultLace[];
};

export const LaceVault = (props) => {
  const { act, data } = useBackend<LaceVaultData>();
  const laces = data.laces || [];

  return (
    <Window width={420} height={480}>
      <Window.Content scrollable>
        <Section
          title={
            data.capacity
              ? `Stored Laces (${laces.length}/${data.capacity})`
              : `Stored Laces (${laces.length})`
          }
          buttons={
            data.network ? (
              <Box inline color="label">
                Network: {data.network}
              </Box>
            ) : null
          }
        >
          {laces.length === 0 ? (
            <NoticeBox>The vault is empty.</NoticeBox>
          ) : (
            <Stack vertical>
              {laces.map((lace) => (
                <Stack.Item key={lace.index}>
                  <Stack align="center">
                    <Stack.Item grow>
                      <Box bold>
                        {lace.index} - Neural Lace ({lace.name})
                        {lace.faction ? ` (${lace.faction})` : ''}
                      </Box>
                      {lace.occupied ? (
                        <Box color="good" fontSize="0.9em">
                          Consciousness stored
                        </Box>
                      ) : lace.was_occupied ? (
                        <Box color="average" fontSize="0.9em">
                          Held a consciousness before the last restart
                        </Box>
                      ) : null}
                      {lace.damage > 0 ? (
                        <Box color="bad" fontSize="0.9em">
                          Integrity damage: {lace.damage}/100
                        </Box>
                      ) : null}
                    </Stack.Item>
                    <Stack.Item>
                      <Button
                        icon="hand-holding"
                        content="Retrieve"
                        onClick={() => act('retrieve', { index: lace.index })}
                      />
                    </Stack.Item>
                  </Stack>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
