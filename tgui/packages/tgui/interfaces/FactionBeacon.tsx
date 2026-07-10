import { Box, Button, NoticeBox, NumberInput, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type FactionBeaconData = {
  faction_uid: string | null;
  faction_name: string | null;
  active: BooleanLike;
  powered: BooleanLike;
  locked: BooleanLike;
  anchored: BooleanLike;
  is_admin: BooleanLike;
  can_configure: BooleanLike;
  refusal_reason: string | null;
  security_radius: number;
};

export const FactionBeacon = (props) => {
  const { act, data } = useBackend<FactionBeaconData>();
  const {
    faction_uid,
    faction_name,
    active,
    powered,
    locked,
    anchored,
    is_admin,
    can_configure,
    refusal_reason,
    security_radius,
  } = data;

  const canTogglePower = anchored && (!locked || is_admin) && can_configure;

  let disabledReason = '';
  if (!anchored) {
    disabledReason = 'Must be wrenched to the floor first.';
  } else if (locked && !is_admin) {
    disabledReason = 'Locked -- alt-click to unlock first.';
  } else if (!can_configure) {
    disabledReason = 'You need command access in this faction.';
  }

  return (
    <Window width={420} height={340} title="Faction Beacon">
      <Window.Content>
        <Section title="Status">
          <Box mb={1}>
            Network:{' '}
            {faction_uid ? (
              <Box inline bold color="good">
                {faction_name}
              </Box>
            ) : (
              <Box inline bold color="average">
                unassigned
              </Box>
            )}
          </Box>
          <Box mb={1}>
            Anchored:{' '}
            <Box inline bold color={anchored ? 'good' : 'bad'}>
              {anchored ? 'Yes' : 'No'}
            </Box>
          </Box>
          <Box mb={1}>
            Locked:{' '}
            <Box inline bold color={locked ? 'bad' : 'good'}>
              {locked ? 'Yes' : 'No'}
            </Box>
          </Box>
          <Box mb={1}>
            Power:{' '}
            <Box inline bold color={powered ? 'good' : 'average'}>
              {powered ? 'On' : 'Off'}
            </Box>
          </Box>
          <Box mb={1}>
            Network active:{' '}
            <Box inline bold color={active ? 'good' : 'average'}>
              {active ? 'Yes' : 'No'}
            </Box>
          </Box>
          {!active && !!refusal_reason && (
            <NoticeBox>Not active: {refusal_reason}.</NoticeBox>
          )}
          <Box mt={1}>
            <Button
              icon="power-off"
              color={powered ? 'bad' : 'good'}
              disabled={!canTogglePower}
              tooltip={disabledReason || undefined}
              onClick={() => act('toggle_power')}
            >
              {powered ? 'Power Off' : 'Power On'}
            </Button>
          </Box>
        </Section>
        {!!is_admin && (
          <Section title="Admin: Force-Set Faction">
            <Button.Input
              content="Set Faction UID"
              onCommit={(value) => act('set_faction', { uid: value })}
            />
            <Button
              icon="times"
              color="bad"
              disabled={!faction_uid}
              onClick={() => act('set_faction', { uid: '' })}
            >
              Clear
            </Button>
          </Section>
        )}
        {!!is_admin && (
          <Section title="Admin: Security Radius">
            <Box mb={1}>
              Overmap sectors beyond this beacon's own Z that get bumped to
              at least medsec (never downgrades highsec, never touches
              another faction's claimed Z):
            </Box>
            <NumberInput
              value={security_radius}
              minValue={0}
              maxValue={10}
              onChange={(value) => act('set_security_radius', { radius: value })}
            />
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};
