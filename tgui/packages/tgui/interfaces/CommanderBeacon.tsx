import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Soldier = {
  ref: string;
  name: string;
  selected: BooleanLike;
};

type CommanderBeaconData = {
  active: BooleanLike;
  stance_mode: string;
  soldier_count: number;
  max_active_mobs: number;
  faction_ready: BooleanLike;
  hostility_mode: string;
  tag_name: string | null;
  preset_name: string | null;
  soldiers: Soldier[];
};

export const CommanderBeacon = (props) => {
  const { act, data } = useBackend<CommanderBeaconData>();
  const {
    active,
    stance_mode,
    soldier_count,
    max_active_mobs,
    faction_ready,
    hostility_mode,
    tag_name,
    preset_name,
    soldiers,
  } = data;

  const selectedSoldiers = (soldiers ?? []).filter((s) => s.selected);

  let disabledReason = '';
  if (!faction_ready) {
    disabledReason = 'You must be a member of a faction.';
  } else if (!preset_name) {
    disabledReason = 'No soldier preset set.';
  }

  return (
    <Window width={380} height={500} title="Commander's Beacon">
      <Window.Content scrollable>
        <Section title="Status">
          <LabeledList>
            <LabeledList.Item label="Status">
              <Box bold color={active ? 'good' : 'bad'}>
                {active ? 'ACTIVE' : 'INACTIVE'}
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Faction">
              <Box color={faction_ready ? 'good' : 'bad'}>
                {faction_ready ? 'Member' : 'Not in a faction'}
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Keyed To">
              {tag_name || 'Personal (untagged)'}
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="power-off"
            content={active ? 'Deactivate' : 'Activate'}
            disabled={!active && !!disabledReason}
            onClick={() => act('toggle')}
          />
          {!active && !!disabledReason && (
            <Box mt={1} color="bad">
              {disabledReason}
            </Box>
          )}
        </Section>
        <Section title="Soldiers">
          <LabeledList>
            <LabeledList.Item label="Preset">{preset_name || 'None set'}</LabeledList.Item>
            <LabeledList.Item label="Count">
              {soldier_count} / {max_active_mobs}
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="user-cog"
            content="Set Preset"
            onClick={() => act('set_preset')}
          />
          <Button
            fluid
            mt={1}
            icon="user-slash"
            content="Dismiss Soldiers"
            disabled={soldier_count === 0}
            onClick={() => act('dismiss')}
          />
          <Button
            fluid
            mt={1}
            icon="street-view"
            content="Fetch"
            disabled={soldier_count === 0}
            onClick={() => act('fetch')}
          />
        </Section>
        {soldier_count > 0 && (
          <Section title="Command Soldier">
            {(soldiers ?? []).map((soldier) => (
              <Button
                key={soldier.ref}
                fluid
                mt={1}
                icon="hand-point-right"
                content={soldier.name}
                selected={soldier.selected}
                onClick={() => act('select_soldier', { ref: soldier.ref })}
              />
            ))}
            {selectedSoldiers.length > 0 && (
              <Box mt={1}>
                <Box color="label">
                  Commanding {selectedSoldiers.length} soldier
                  {selectedSoldiers.length > 1 ? 's' : ''} -- click a location
                  anywhere visible to send them there, or click an enemy to
                  focus them down. Keep clicking to issue more orders;
                  deselect or close this window when done.
                </Box>
                <Button
                  fluid
                  mt={1}
                  icon="crosshairs"
                  content="Clear Target"
                  onClick={() => act('clear_attack_target')}
                />
                <Button
                  fluid
                  mt={1}
                  icon="times"
                  content="Cancel Selection"
                  onClick={() => act('clear_selection')}
                />
              </Box>
            )}
          </Section>
        )}
        <Section title="Orders">
          <Button
            fluid
            mt={1}
            icon="walking"
            content="Follow"
            selected={stance_mode === 'follow'}
            onClick={() => act('set_follow')}
          />
          <Button
            fluid
            mt={1}
            icon="shield-alt"
            content="Hold Position"
            selected={stance_mode === 'hold'}
            onClick={() => act('set_hold')}
          />
        </Section>
        <Section title="Hostility">
          <Button
            fluid
            mt={1}
            icon="crosshairs"
            content="Hostile"
            selected={hostility_mode === 'hostile'}
            onClick={() => act('set_hostile')}
          />
          <Button
            fluid
            mt={1}
            icon="hand-paper"
            content="Passive"
            selected={hostility_mode === 'passive'}
            onClick={() => act('set_passive')}
          />
        </Section>
        <Section title="Guard Beacons (this level)">
          <Box color="label">
            Affects guard beacons only -- posted guards on this level tagged
            to your faction. Does not affect your own followers above.
          </Box>
          <Button
            fluid
            mt={1}
            icon="power-off"
            content="Enable All Guards"
            onClick={() => act('set_all_guards_enabled')}
          />
          <Button
            fluid
            mt={1}
            icon="ban"
            content="Disable All Guards"
            onClick={() => act('set_all_guards_disabled')}
          />
          <Button
            fluid
            mt={1}
            icon="crosshairs"
            content="Set All Guards Hostile"
            onClick={() => act('set_all_guards_hostile')}
          />
          <Button
            fluid
            mt={1}
            icon="hand-paper"
            content="Set All Guards Passive"
            onClick={() => act('set_all_guards_passive')}
          />
        </Section>
        <Section title="Faction Turrets (this level)">
          <Box color="label">
            Affects every portable turret on this level tagged to your
            faction -- not just guard beacons or your own followers above.
          </Box>
          <Button
            fluid
            mt={1}
            icon="power-off"
            content="Enable Turrets"
            onClick={() => act('set_turrets_enabled')}
          />
          <Button
            fluid
            mt={1}
            icon="ban"
            content="Disable Turrets"
            onClick={() => act('set_turrets_disabled')}
          />
          <Button
            fluid
            mt={1}
            icon="skull"
            content="Set Turrets Lethal"
            onClick={() => act('set_turrets_lethal')}
          />
          <Button
            fluid
            mt={1}
            icon="bolt"
            content="Set Turrets Stun"
            onClick={() => act('set_turrets_stun')}
          />
        </Section>
      </Window.Content>
    </Window>
  );
};
