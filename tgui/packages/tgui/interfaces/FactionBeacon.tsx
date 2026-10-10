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
  site_name: string | null;
  public_territory: BooleanLike;
  drydock_stash_policy: string;
  faction_raiding_enabled: BooleanLike;
  hazard_eviction_active: BooleanLike;
  is_hub: BooleanLike;
  restrict_to_hub_personnel?: BooleanLike;
};

// Who may stash, retrieve or commission a ship at any drydock this claim reaches.
// Values must match DRYDOCK_POLICY_* in code/__DEFINES/persistence.dm.
const DRYDOCK_POLICIES: {
  value: string;
  label: string;
  tooltip: string;
}[] = [
  {
    value: 'all',
    label: 'Anyone',
    tooltip: 'Any ship may use drydocks in range. This is the default.',
  },
  {
    value: 'faction',
    label: 'Faction Only',
    tooltip: "Only this faction's own ships, and its members' personal ships.",
  },
  {
    value: 'allied',
    label: 'Faction + Allies',
    tooltip:
      "This faction and any allied faction, including their members' personal ships.",
  },
  {
    value: 'none',
    label: 'Closed',
    tooltip: 'No ship may be stashed, retrieved or built at drydocks in range.',
  },
];

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
    site_name,
    public_territory,
    drydock_stash_policy,
    faction_raiding_enabled,
    hazard_eviction_active,
    is_hub,
    restrict_to_hub_personnel,
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
    <Window
      width={420}
      height={requires_fuel ? 500 : is_hub ? 380 : 340}
      title="Faction Beacon"
    >
      <Window.Content scrollable>
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
          <Box mb={1}>
            Territory:{' '}
            <Box inline bold color={public_territory ? 'average' : 'good'}>
              {public_territory ? 'Public' : 'Private'}
            </Box>
            {!public_territory && !!faction_raiding_enabled && (
              <Box inline color="label">
                {' '}
                (no effect right now -- raiding is enabled server-wide)
              </Box>
            )}
          </Box>
          <Box mb={1}>
            Drydock access:{' '}
            <Box
              inline
              bold
              color={drydock_stash_policy === 'all' ? 'average' : 'good'}
            >
              {DRYDOCK_POLICIES.find((p) => p.value === drydock_stash_policy)
                ?.label ?? drydock_stash_policy}
            </Box>
          </Box>
          {!!is_hub && (
            <Box mb={1}>
              Access:{' '}
              <Box
                inline
                bold
                color={restrict_to_hub_personnel ? 'good' : 'average'}
              >
                {restrict_to_hub_personnel ? 'Hub Personnel Only' : 'Open'}
              </Box>
            </Box>
          )}
          {!active && !!refusal_reason && (
            <NoticeBox>Not active: {refusal_reason}.</NoticeBox>
          )}
          {!!site_name && (
            <Box mb={1}>
              Site:{' '}
              <Box inline bold>
                {site_name}
              </Box>{' '}
              <Button
                icon="pen"
                disabled={!can_configure}
                tooltip={disabledReason || undefined}
                onClick={() => act('rename_site')}
              >
                Rename Site
              </Button>
            </Box>
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
            <Button
              icon="unlock"
              color={public_territory ? 'average' : 'good'}
              disabled={!can_configure}
              tooltip={
                can_configure
                  ? 'Public territory lets non-members enter regardless of the admin faction raiding toggle. Private is subject to it like any other claimed territory.'
                  : 'You need command access in this faction.'
              }
              onClick={() => act('toggle_public_territory')}
            >
              Make Territory {public_territory ? 'Private' : 'Public'}
            </Button>
            {!!is_hub && (
              <Button
                icon="user-shield"
                color={restrict_to_hub_personnel ? 'good' : 'average'}
                disabled={!can_configure}
                tooltip={
                  can_configure
                    ? 'Hub Personnel Only lets in Hub-affiliated personnel actually holding a job (and admins) -- a civilian-rank Hub ID does not qualify. Open lets anyone travel, warp, or disembark here.'
                    : 'You need command access in this faction.'
                }
                onClick={() => act('toggle_hub_personnel_restriction')}
              >
                Make Access {restrict_to_hub_personnel ? 'Open' : 'Hub Personnel Only'}
              </Button>
            )}
          </Box>
          <Box mt={1}>
            <Box inline mr={1} color="label">
              Drydock access:
            </Box>
            {DRYDOCK_POLICIES.map((policy) => (
              <Button
                key={policy.value}
                selected={drydock_stash_policy === policy.value}
                disabled={!can_configure}
                tooltip={
                  can_configure
                    ? policy.tooltip
                    : 'You need command access in this faction.'
                }
                onClick={() =>
                  act('set_drydock_policy', { policy: policy.value })
                }
              >
                {policy.label}
              </Button>
            ))}
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
            <Box mt={1} color={hazard_eviction_active ? 'good' : 'bad'}>
              Hazard eviction: {hazard_eviction_active ? 'Active' : 'Inactive'}
              {!hazard_eviction_active &&
                ' -- raise the radius above 0 and reach medsec or better to start clearing hazards in range.'}
            </Box>
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};
