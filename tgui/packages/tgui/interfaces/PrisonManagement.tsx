import { Box, Button, NoticeBox, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Prisoner = {
  ckey: string;
  char_name: string;
  indefinite: BooleanLike;
  remaining_seconds: number;
  locked: BooleanLike;
};

type PrisonManagementData = {
  faction_uid: string | null;
  faction_name: string | null;
  prisoners: Prisoner[];
};

const formatRemaining = (seconds: number) => {
  const total = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
};

export const PrisonManagement = (props) => {
  const { act, data } = useBackend<PrisonManagementData>();
  const { faction_uid, faction_name, prisoners = [] } = data;

  if (!faction_uid) {
    return (
      <NtosWindow width={550} height={400}>
        <NtosWindow.Content scrollable>
          <NoticeBox>
            This console is not linked to a faction. Tag it with a faction
            tagger tool first.
          </NoticeBox>
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  return (
    <NtosWindow width={550} height={400}>
      <NtosWindow.Content scrollable>
        <Section title={`${faction_name ?? faction_uid} -- Prison Management`}>
          {prisoners.length === 0 ? (
            <Box italic color="label">
              No one is currently imprisoned.
            </Box>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Name</Table.Cell>
                <Table.Cell>Sentence</Table.Cell>
                <Table.Cell>Status</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {prisoners.map((p) => (
                <Table.Row key={`${p.ckey}|${p.char_name}`}>
                  <Table.Cell bold>{p.char_name}</Table.Cell>
                  <Table.Cell>
                    {p.indefinite
                      ? 'Indefinite'
                      : formatRemaining(p.remaining_seconds)}
                  </Table.Cell>
                  <Table.Cell color={p.locked ? 'bad' : 'good'}>
                    {p.locked ? 'Locked' : 'Unlocked'}
                  </Table.Cell>
                  <Table.Cell>
                    <Button
                      compact
                      icon={p.locked ? 'unlock' : 'lock'}
                      onClick={() =>
                        act('toggle_lock', {
                          ckey: p.ckey,
                          char_name: p.char_name,
                        })
                      }
                    >
                      {p.locked ? 'Unlock' : 'Lock'}
                    </Button>
                    <Button
                      compact
                      icon="clock"
                      onClick={() =>
                        act('adjust', { ckey: p.ckey, char_name: p.char_name })
                      }
                    >
                      Adjust
                    </Button>
                    <Button
                      compact
                      color="good"
                      icon="door-open"
                      onClick={() =>
                        act('release', {
                          ckey: p.ckey,
                          char_name: p.char_name,
                        })
                      }
                    >
                      Release
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
