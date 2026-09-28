import { Box, Button, NoticeBox, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type DrydockControlData = {
  anchored: BooleanLike;
  on_drydock: BooleanLike;
  faction_uid: string | null;
  faction_name: string | null;
  drydock_stash_policy: string;
  can_configure: BooleanLike;
  overridden_by: string | null;
  legacy_stashing: BooleanLike;
};

// Values must match DRYDOCK_POLICY_* in code/__DEFINES/persistence.dm.
const DRYDOCK_POLICIES: {
  value: string;
  label: string;
  tooltip: string;
}[] = [
  {
    value: 'all',
    label: 'Anyone',
    tooltip: 'Any ship may berth here. This is the default.',
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
    tooltip: 'No ship may be stashed, retrieved or built here.',
  },
];

export const DrydockControl = (props) => {
  const { act, data } = useBackend<DrydockControlData>();
  const {
    anchored,
    on_drydock,
    faction_name,
    drydock_stash_policy,
    can_configure,
    overridden_by,
    legacy_stashing,
  } = data;

  const current = DRYDOCK_POLICIES.find(
    (p) => p.value === drydock_stash_policy,
  );

  return (
    <Window title="Drydock Control" width={420} height={360}>
      <Window.Content scrollable>
        {!anchored && (
          <NoticeBox warning>
            Not secured -- wrench this console down before it registers with the
            traffic authority.
          </NoticeBox>
        )}
        {!!anchored && !on_drydock && (
          <NoticeBox warning>
            This site is not a drydock, so there are no berthing rights to set.
            A drydock has to be founded here first.
          </NoticeBox>
        )}
        {!!legacy_stashing && (
          <NoticeBox>
            Legacy stashing is enabled server-wide -- ships do not currently
            need a drydock at all, and this setting is being ignored.
          </NoticeBox>
        )}
        {!!overridden_by && (
          <NoticeBox>
            Overridden by {overridden_by}: a faction beacon covering this drydock
            sets its policy, and this console has no effect while that is true.
          </NoticeBox>
        )}
        <Section title="Berthing Rights">
          <Box mb={1}>
            Registered to:{' '}
            <Box inline bold color={faction_name ? 'good' : 'average'}>
              {faction_name || 'Nobody (untagged)'}
            </Box>
          </Box>
          <Box mb={1}>
            Current:{' '}
            <Box
              inline
              bold
              color={drydock_stash_policy === 'all' ? 'average' : 'good'}
            >
              {current?.label ?? drydock_stash_policy}
            </Box>
          </Box>
          <Box color="label" mb={1}>
            {current?.tooltip}
          </Box>
          <Box mt={1}>
            {DRYDOCK_POLICIES.map((policy) => (
              <Button
                key={policy.value}
                selected={drydock_stash_policy === policy.value}
                disabled={!can_configure || !on_drydock || !anchored}
                tooltip={
                  !anchored
                    ? 'Secure this console first.'
                    : !on_drydock
                      ? 'This site is not a drydock.'
                      : can_configure
                        ? policy.tooltip
                        : 'You need command access in this console’s faction.'
                }
                onClick={() => act('set_policy', { policy: policy.value })}
              >
                {policy.label}
              </Button>
            ))}
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
