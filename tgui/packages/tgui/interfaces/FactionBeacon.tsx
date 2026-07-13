import { useState } from 'react';
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
  fuel_credits: number;
  max_fuel_credits: number;
  requires_fuel: BooleanLike;
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
    fuel_credits,
    max_fuel_credits,
    requires_fuel,
  } = data;
  const [withdrawAmount, setWithdrawAmount] = useState(0);

  const canTogglePower = anchored && (!locked || is_admin) && can_configure;
  const fuelRatio = max_fuel_credits > 0 ? fuel_credits / max_fuel_credits : 0;
  const fuelColor =
    fuelRatio > 0.66 ? 'good' : fuelRatio > 0.33 ? 'average' : 'bad';

  let disabledReason = '';
  if (!anchored) {
    disabledReason = 'Must be wrenched to the floor first.';
  } else if (locked && !is_admin) {
    disabledReason = 'Locked -- alt-click to unlock first.';
  } else if (!can_configure) {
    disabledReason = 'You need command access in this faction.';
  }

  return (
    <Window width={420} height={requires_fuel ? 500 : 340} title="Faction Beacon">
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
        {!!requires_fuel && (
          <Section title="Fuel Reserve">
            <Box mb={1}>
              Reserve:{' '}
              <Box inline bold color={fuelColor}>
                {fuel_credits} / {max_fuel_credits} cr
              </Box>
            </Box>
            <Box color="label" mb={1}>
              Insert credit chips (not charge cards) to add fuel. Drains
              slowly while powered -- an empty reserve auto-powers the beacon
              off.
            </Box>
            <NumberInput
              value={withdrawAmount}
              minValue={0}
              maxValue={fuel_credits}
              onChange={(value) => setWithdrawAmount(value)}
            />
            <Button
              icon="money-bill-wave"
              color="average"
              ml={1}
              disabled={!canTogglePower || withdrawAmount <= 0}
              onClick={() => {
                act('withdraw', { amount: withdrawAmount });
                setWithdrawAmount(0);
              }}
            >
              Withdraw
            </Button>
          </Section>
        )}
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
