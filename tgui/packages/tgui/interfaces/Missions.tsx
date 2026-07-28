import { Box, Button, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Mission = {
  id: number;
  mission_type: 'fetch' | 'kill' | 'visit';
  title: string;
  description: string;
  fetch_count: number | null;
  kill_count: number | null;
  sector_template_id: string | null;
  reward: number;
  claimed_by_me: BooleanLike;
  claimed: BooleanLike;
  objective_complete: BooleanLike;
};

type MissionsData = {
  status_message: string;
  my_ckey: string;
  missions: Mission[];
};

export const Missions = (props) => {
  const { act, data } = useBackend<MissionsData>();
  const { status_message, missions } = data;

  return (
    <NtosWindow resizable width={700} height={600}>
      <NtosWindow.Content scrollable>
        <Section title="Missions Board">
          <Box color="label" mb={1}>
            Fetch missions are turned in once you're carrying the required
            items. Visit missions complete the moment you reach the target
            sector -- leave the sector and turn the mission in to collect
            payment.
          </Box>
          {status_message && (
            <Box
              bold
              mb={1}
              color={
                status_message.includes('Failed') ||
                status_message.includes("Can't") ||
                status_message.includes('own')
                  ? 'bad'
                  : 'good'
              }
            >
              {status_message}
            </Box>
          )}

          <Table>
            <Table.Row header>
              <Table.Cell>Title</Table.Cell>
              <Table.Cell>Type</Table.Cell>
              <Table.Cell>Description</Table.Cell>
              <Table.Cell>Reward</Table.Cell>
              <Table.Cell>Action</Table.Cell>
            </Table.Row>
            {(missions ?? []).map((mission) => (
              <Table.Row key={mission.id}>
                <Table.Cell bold>{mission.title}</Table.Cell>
                <Table.Cell>
                  {mission.mission_type === 'fetch' &&
                    `Fetch x${mission.fetch_count}`}
                  {mission.mission_type === 'visit' && 'Visit Site'}
                  {mission.mission_type === 'kill' &&
                    `Kill x${mission.kill_count}`}
                </Table.Cell>
                <Table.Cell>{mission.description}</Table.Cell>
                <Table.Cell>{mission.reward} cr</Table.Cell>
                <Table.Cell>
                  {!mission.claimed && (
                    <Button
                      icon="check"
                      color="good"
                      onClick={() =>
                        act('accept_mission', { id: mission.id })
                      }
                    >
                      Accept
                    </Button>
                  )}
                  {mission.claimed && !mission.claimed_by_me && (
                    <Box color="label" inline bold>
                      Claimed
                    </Box>
                  )}
                  {mission.claimed_by_me && (
                    <>
                      {mission.mission_type === 'fetch' ||
                      mission.objective_complete ? (
                        <Button
                          icon="hand-holding-usd"
                          color="good"
                          onClick={() =>
                            act('turn_in_mission', { id: mission.id })
                          }
                        >
                          Turn In
                        </Button>
                      ) : (
                        <Box color="average" inline bold>
                          In Progress
                        </Box>
                      )}
                      <Button
                        icon="times"
                        color="bad"
                        ml={1}
                        onClick={() =>
                          act('abandon_mission', { id: mission.id })
                        }
                      >
                        Abandon
                      </Button>
                    </>
                  )}
                </Table.Cell>
              </Table.Row>
            ))}
            {!missions?.length && (
              <Table.Row>
                <Table.Cell colSpan={5}>
                  <Box color="label">No missions available.</Box>
                </Table.Cell>
              </Table.Row>
            )}
          </Table>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
