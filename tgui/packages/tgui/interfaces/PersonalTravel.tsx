import { Box, Button, NoticeBox, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type BeaconDestination = {
  ref: string;
  name: string;
};

type PrimedTarget = {
  ref: string;
  name: string;
  distance: number;
};

type PersonalTravelData = {
  sector_name: string;
  territory_faction: string | null;
  primed: PrimedTarget | null;
  is_away_site: BooleanLike;
  viewing: BooleanLike;
  in_combat: BooleanLike;
  combat_seconds_left: number;
  cooldown_seconds_left: number;
  has_hardsuit: BooleanLike;
  beacon_destinations: BeaconDestination[];
};

export const PersonalTravel = (props) => {
  const { act, data } = useBackend<PersonalTravelData>();
  const {
    sector_name,
    territory_faction,
    primed,
    viewing,
    in_combat,
    combat_seconds_left,
    cooldown_seconds_left,
    has_hardsuit,
    beacon_destinations,
  } = data;

  const gateReason = in_combat
    ? `Recent combat detected -- locked for ${combat_seconds_left}s.`
    : cooldown_seconds_left > 0
      ? `Recalibrating -- ${cooldown_seconds_left}s remaining.`
      : null;
  const actionsDisabled = !!gateReason;

  return (
    <NtosWindow width={480} height={520}>
      <NtosWindow.Content scrollable>
        <Section title="Current Position">
          <Box mb={1}>
            You are at:{' '}
            <Box inline bold color="good">
              {sector_name}
            </Box>
          </Box>
          {!!territory_faction && (
            <Box mb={1} color="average">
              You are in {territory_faction} territory.
            </Box>
          )}
          <Button
            icon="satellite-dish"
            color={viewing ? 'good' : 'grey'}
            onClick={() => act('toggle_view')}
          >
            {viewing ? 'Close Sector View' : 'Open Sector View'}
          </Button>
        </Section>

        {!!gateReason && <NoticeBox danger>{gateReason}</NoticeBox>}

        <Section title="Leap">
          <NoticeBox info>
            Leaping drops you on open space near the target -- a hardsuit is
            required. A 15-second bluespace calibration is audible to nearby
            people and can be interrupted.
          </NoticeBox>
          {!has_hardsuit && (
            <NoticeBox danger>
              No hardsuit worn -- Leap is unavailable.
            </NoticeBox>
          )}
          {!!primed && (
            <Box mb={1}>
              Primed target:{' '}
              <Box inline bold color="good">
                {primed.name}
              </Box>{' '}
              <Box inline color="label">
                (distance {primed.distance})
              </Box>{' '}
              <Button
                icon="bolt"
                color="good"
                disabled={actionsDisabled || !has_hardsuit}
                onClick={() => act('leap')}
              >
                Leap
              </Button>
            </Box>
          )}
          {!primed && (
            <Box italic color="label">
              No destination primed -- open Sector View and click a target to
              prime one.
            </Box>
          )}
        </Section>

        <Section title="Return to Beacon">
          {beacon_destinations.length === 0 && (
            <Box italic color="label">
              No faction beacon in range to return to.
            </Box>
          )}
          {beacon_destinations.length > 0 && (
            <Table>
              <Table.Row header>
                <Table.Cell>Beacon</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {beacon_destinations.map((beacon) => (
                <Table.Row key={beacon.ref} className="candystripe">
                  <Table.Cell bold>{beacon.name}</Table.Cell>
                  <Table.Cell>
                    <Button
                      icon="reply"
                      color="good"
                      disabled={actionsDisabled}
                      onClick={() =>
                        act('return_beacon', { beacon_ref: beacon.ref })
                      }
                    >
                      Return
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>

        <Section title="Return to Hub">
          <Button
            icon="home"
            color="good"
            disabled={actionsDisabled}
            onClick={() => act('return_hub')}
          >
            Return to Hub
          </Button>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
