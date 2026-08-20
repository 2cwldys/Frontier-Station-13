import { useState } from 'react';
import {
  Box,
  Button,
  Dropdown,
  LabeledList,
  NoticeBox,
  NumberInput,
  Section,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Preset = {
  id: number;
  name: string;
};

type Faction = {
  uid: string;
  name: string;
};

type SpawnGroup = {
  ref: string;
  label: string;
  creator_name: string;
  faction_name: string;
  alive: number;
  total: number;
  location: string;
};

type HostileSpawnPanelData = {
  presets: Preset[];
  factions: Faction[];
  groups: SpawnGroup[];
  placing: BooleanLike;
};

export const HostileSpawnPanel = (props) => {
  const { act, data } = useBackend<HostileSpawnPanelData>();
  const { presets = [], factions = [], groups = [], placing } = data;

  const [presetIds, setPresetIds] = useState<number[]>(
    presets[0] ? [presets[0].id] : [],
  );
  const [count, setCount] = useState(1);
  const [relationship, setRelationship] = useState<'hostile' | 'allied'>(
    'hostile',
  );
  const [factionUid, setFactionUid] = useState('');

  const togglePreset = (id: number) => {
    setPresetIds((prev) =>
      prev.includes(id) ? prev.filter((p) => p !== id) : [...prev, id],
    );
  };

  const selectedFaction = factions.find((f) => f.uid === factionUid);
  const canSpawn =
    presetIds.length > 0 && (relationship === 'hostile' || !!factionUid);

  const spawnParams = () => ({
    preset_ids: presetIds,
    count,
    relationship,
    faction_uid: factionUid,
  });

  return (
    <Window width={480} height={600} title="Spawn Faction AI">
      <Window.Content scrollable>
        <Section title="Spawn">
          {!!placing && (
            <NoticeBox>
              Placement mode is active -- left click a tile in-game to spawn
              there, right click an admin-spawned hostile to remove it. Use
              the eye's "Stop looking" action to exit.
            </NoticeBox>
          )}
          {presets.length === 0 ? (
            <NoticeBox>
              No enabled hostile NPC presets exist -- create one via "Manage
              Hostile NPC Presets" first.
            </NoticeBox>
          ) : (
            <LabeledList>
              <LabeledList.Item label="Presets" verticalAlign="top">
                <Box color="label" mb={0.5}>
                  Select one or more -- each individual spawn randomly picks
                  one from your selection, so a batch or placement session
                  isn&apos;t all the same loadout.
                </Box>
                <Box mb={0.5}>
                  <Button
                    compact
                    icon="check-double"
                    onClick={() => setPresetIds(presets.map((p) => p.id))}
                  >
                    Select All
                  </Button>
                  <Button
                    compact
                    icon="times"
                    onClick={() => setPresetIds([])}
                  >
                    Clear
                  </Button>
                </Box>
                {presets.map((p) => (
                  <Button
                    key={p.id}
                    mb={0.5}
                    mr={0.5}
                    selected={presetIds.includes(p.id)}
                    onClick={() => togglePreset(p.id)}
                  >
                    {p.name}
                  </Button>
                ))}
              </LabeledList.Item>
              <LabeledList.Item label="Count">
                <NumberInput
                  value={count}
                  minValue={1}
                  maxValue={20}
                  width={3}
                  step={1}
                  stepPixelSize={5}
                  animated
                  onChange={(value) => setCount(value)}
                />
                <Box inline color="label" ml={1}>
                  (placement mode always spawns one at a time)
                </Box>
              </LabeledList.Item>
              <LabeledList.Item label="Relationship">
                <Button
                  selected={relationship === 'hostile'}
                  icon="skull-crossbones"
                  onClick={() => setRelationship('hostile')}
                >
                  Hostile to All
                </Button>
                <Button
                  selected={relationship === 'allied'}
                  icon="handshake"
                  onClick={() => setRelationship('allied')}
                >
                  Allied with Faction
                </Button>
              </LabeledList.Item>
              {relationship === 'allied' && (
                <LabeledList.Item label="Faction">
                  {factions.length === 0 ? (
                    <Box color="bad">No factions exist.</Box>
                  ) : (
                    <Dropdown
                      width="100%"
                      selected={
                        selectedFaction?.name ?? 'Select a faction...'
                      }
                      options={factions.map((f) => f.name)}
                      onSelected={(name) => {
                        const match = factions.find((f) => f.name === name);
                        setFactionUid(match ? match.uid : '');
                      }}
                    />
                  )}
                </LabeledList.Item>
              )}
            </LabeledList>
          )}
          <Box mt={1}>
            <Button
              icon="street-view"
              color="good"
              disabled={!canSpawn}
              onClick={() => act('spawn', spawnParams())}
            >
              Spawn Here
            </Button>
            <Button
              icon="crosshairs"
              disabled={!canSpawn || !!placing}
              onClick={() => act('enter_placement_mode', spawnParams())}
            >
              Enter Placement Mode
            </Button>
          </Box>
        </Section>
        <Section title="Active Groups">
          {groups.length === 0 ? (
            <NoticeBox>No tracked hostile spawn groups right now.</NoticeBox>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Group</Table.Cell>
                <Table.Cell>Relationship</Table.Cell>
                <Table.Cell>Alive</Table.Cell>
                <Table.Cell>Location</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {groups.map((group) => (
                <Table.Row key={group.ref}>
                  <Table.Cell>
                    {group.label}
                    <Box color="label" fontSize="0.9em">
                      by {group.creator_name}
                    </Box>
                  </Table.Cell>
                  <Table.Cell>{group.faction_name}</Table.Cell>
                  <Table.Cell>
                    {group.alive} / {group.total}
                  </Table.Cell>
                  <Table.Cell>{group.location}</Table.Cell>
                  <Table.Cell>
                    <Button
                      icon="times"
                      color="bad"
                      onClick={() => act('dismiss_group', { ref: group.ref })}
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
