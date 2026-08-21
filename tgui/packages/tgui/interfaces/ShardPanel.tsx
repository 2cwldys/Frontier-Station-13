import { useState } from 'react';
import {
  Box,
  Button,
  Input,
  LabeledList,
  NoticeBox,
  Section,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Shard = {
  shard_id: string;
  port: number;
  status: 'running' | 'stopped';
  created_at: string;
  started_at: string;
};

type ShardPanelData = {
  shards: Shard[];
  auto_threshold: number;
  central_unreachable: BooleanLike;
};

export const ShardPanel = (props) => {
  const { act, data } = useBackend<ShardPanelData>();
  const { shards = [], central_unreachable } = data;

  const [newShardId, setNewShardId] = useState('');
  const [newPort, setNewPort] = useState('');

  const canCreate = newShardId.trim().length > 0 && newPort.trim().length > 0;

  return (
    <Window width={640} height={480} title="Manage Shards">
      <Window.Content scrollable>
        {!!central_unreachable && (
          <NoticeBox danger>
            The central database is unreachable -- shard actions won't work
            until it's back.
          </NoticeBox>
        )}
        <Section title="Create Shard">
          <NoticeBox>
            A shard is a second, independent game server on this machine,
            sharing this server's central database (characters/admins/
            etc.) but starting with completely fresh local data (turfs,
            objects, machinery). Creating one can take a while the first
            time (it builds the shard runtime image).
          </NoticeBox>
          <LabeledList>
            <LabeledList.Item label="Shard ID">
              <Input
                width="100%"
                placeholder="letters, digits, hyphen, underscore only"
                value={newShardId}
                onInput={(_, value) => setNewShardId(value)}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Port">
              <Input
                width="100%"
                placeholder="must be free on this host"
                value={newPort}
                onInput={(_, value) => setNewPort(value)}
              />
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1}>
            <Button
              icon="plus"
              color="good"
              disabled={!canCreate}
              onClick={() => {
                act('create', { shard_id: newShardId.trim(), port: newPort.trim() });
                setNewShardId('');
                setNewPort('');
              }}
            >
              Create
            </Button>
          </Box>
        </Section>
        <Section title="Shards">
          {shards.length === 0 ? (
            <NoticeBox>No shards registered yet.</NoticeBox>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Shard</Table.Cell>
                <Table.Cell>Port</Table.Cell>
                <Table.Cell>Status</Table.Cell>
                <Table.Cell>Created</Table.Cell>
                <Table.Cell>Last Started</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {shards.map((shard) => (
                <Table.Row key={shard.shard_id}>
                  <Table.Cell>{shard.shard_id}</Table.Cell>
                  <Table.Cell>{shard.port}</Table.Cell>
                  <Table.Cell>
                    <Box color={shard.status === 'running' ? 'good' : 'label'}>
                      {shard.status}
                    </Box>
                  </Table.Cell>
                  <Table.Cell>{shard.created_at}</Table.Cell>
                  <Table.Cell>{shard.started_at || '--'}</Table.Cell>
                  <Table.Cell>
                    {shard.status === 'running' ? (
                      <Button
                        icon="stop"
                        color="average"
                        onClick={() => act('stop', { shard_id: shard.shard_id })}
                      >
                        Stop
                      </Button>
                    ) : (
                      <Button
                        icon="play"
                        color="good"
                        onClick={() => act('start', { shard_id: shard.shard_id })}
                      >
                        Start
                      </Button>
                    )}
                    <Button
                      icon="trash"
                      color="bad"
                      onClick={() => {
                        if (
                          confirm(
                            `Permanently remove shard '${shard.shard_id}'? This deletes its containers, local data, and central DB login. This cannot be undone.`,
                          )
                        ) {
                          act('remove', { shard_id: shard.shard_id });
                        }
                      }}
                    >
                      Remove
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
