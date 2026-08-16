import { Box, Button, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Data = {
  bound: BooleanLike;
  faction_uid: string | null;
  faction_name: string | null;
  cooldown_seconds_left: number;
  is_self: BooleanLike;
  target_name: string;
};

export const FactionBoundStatus = (_props) => {
  const { act, data } = useBackend<Data>();
  const bound = !!data.bound;
  const isSelf = !!data.is_self;
  const onCooldown = data.cooldown_seconds_left > 0;

  return (
    <Window
      width={380}
      height={220}
      title={isSelf ? 'Shackle Status' : `${data.target_name} -- Shackle Status`}
    >
      <Window.Content scrollable>
        <Section title="Status">
          {bound ? (
            <Box mb={1}>
              {isSelf ? 'Shackled to:' : `${data.target_name} is shackled to:`}{' '}
              <Box inline bold color="bad">
                {data.faction_name}
              </Box>
            </Box>
          ) : (
            <Box mb={1} color="good">
              {isSelf ? 'Not shackled.' : `${data.target_name} is not shackled.`}
            </Box>
          )}
          {bound && isSelf && (
            <>
              <Box mb={1} color="label">
                Attempting to overload the shackle always alerts the
                faction holding it, whether you succeed or not. A failed
                attempt will hurt -- badly, but never fatally or costs you
                a limb.
              </Box>
              <Button
                fluid
                icon="bolt"
                content={
                  onCooldown
                    ? `Attempt to Break Free (${data.cooldown_seconds_left}s)`
                    : 'Attempt to Break Free'
                }
                color="bad"
                disabled={onCooldown}
                tooltip={onCooldown ? 'Recovering from the last attempt.' : undefined}
                onClick={() => act('break_free')}
              />
            </>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};

export default FactionBoundStatus;
