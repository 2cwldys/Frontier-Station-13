import { Box, Button, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Bounty = {
  id: number;
  target_name: string;
  reward: number;
  status: string;
  poster_ckey: string;
  accepter_count: number;
  accepted_by_me: BooleanLike;
};

type BountiesData = {
  status_message: string;
  my_ckey: string;
  bounties: Bounty[];
};

export const Bounties = (props) => {
  const { act, data } = useBackend<BountiesData>();
  const { status_message, my_ckey, bounties } = data;

  return (
    <NtosWindow resizable width={650} height={550}>
      <NtosWindow.Content scrollable>
        <Section
          title="Post a Bounty"
          buttons={
            <Button
              icon="crosshairs"
              color="good"
              onClick={() => act('post_bounty')}
            >
              Post Bounty
            </Button>
          }
        >
          <Box color="label">
            Name a character and put credits on their head. Anyone can accept
            an open bounty -- whoever actually lands the kill collects the
            reward.
          </Box>
          {status_message && (
            <Box
              bold
              mt={1}
              color={
                status_message.includes('Failed') ||
                status_message.includes('cannot')
                  ? 'bad'
                  : 'good'
              }
            >
              {status_message}
            </Box>
          )}
        </Section>

        <Section title="Bounty Board">
          <Table>
            <Table.Row header>
              <Table.Cell>Target</Table.Cell>
              <Table.Cell>Reward</Table.Cell>
              <Table.Cell>Accepters</Table.Cell>
              <Table.Cell>Action</Table.Cell>
            </Table.Row>
            {(bounties ?? []).map((bounty) => (
              <Table.Row key={bounty.id}>
                <Table.Cell>{bounty.target_name}</Table.Cell>
                <Table.Cell>{bounty.reward} cr</Table.Cell>
                <Table.Cell>{bounty.accepter_count}</Table.Cell>
                <Table.Cell>
                  {bounty.accepted_by_me ? (
                    <Box color="good" inline bold>
                      Accepted
                    </Box>
                  ) : (
                    <Button
                      icon="check"
                      color="good"
                      onClick={() =>
                        act('accept_bounty', { id: bounty.id })
                      }
                    >
                      Accept
                    </Button>
                  )}
                  {bounty.poster_ckey === my_ckey && (
                    <Button
                      icon="times"
                      color="bad"
                      ml={1}
                      onClick={() =>
                        act('cancel_bounty', { id: bounty.id })
                      }
                    >
                      Cancel
                    </Button>
                  )}
                </Table.Cell>
              </Table.Row>
            ))}
            {!bounties?.length && (
              <Table.Row>
                <Table.Cell colSpan={4}>
                  <Box color="label">No open bounties.</Box>
                </Table.Cell>
              </Table.Row>
            )}
          </Table>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
