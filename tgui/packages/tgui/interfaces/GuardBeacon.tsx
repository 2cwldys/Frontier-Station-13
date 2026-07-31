import { Box, Button, Dropdown, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type GuardBeaconData = {
  active: BooleanLike;
  anchored: BooleanLike;
  faction_name: string | null;
  faction_ready: BooleanLike;
  can_configure: BooleanLike;
  soldier_count: number;
  max_active_mobs: number;
  hostility_mode: string;
  preset_name: string | null;
  facing: string;
  facing_options: string[];
};

export const GuardBeacon = (props) => {
  const { act, data } = useBackend<GuardBeaconData>();
  const {
    active,
    anchored,
    faction_name,
    faction_ready,
    can_configure,
    soldier_count,
    max_active_mobs,
    hostility_mode,
    preset_name,
    facing,
    facing_options,
  } = data;

  let disabledReason = '';
  if (!anchored) {
    disabledReason = 'Must be wrenched to the floor first.';
  } else if (!faction_ready) {
    disabledReason = 'Must be tagged to a real faction (not personal/public/crew).';
  } else if (!preset_name) {
    disabledReason = 'No soldier preset set.';
  }

  return (
    <Window width={380} height={480} title="Guard Beacon">
      <Window.Content scrollable>
        <Section title="Status">
          <LabeledList>
            <LabeledList.Item label="Power">
              <Box bold color={active ? 'good' : 'bad'}>
                {active ? 'ACTIVE' : 'OFFLINE'}
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Anchored">
              <Box color={anchored ? 'good' : 'bad'}>{anchored ? 'Yes' : 'No'}</Box>
            </LabeledList.Item>
            <LabeledList.Item label="Faction">
              <Box color={faction_ready ? 'good' : 'bad'}>
                {faction_name || 'Not tagged to a faction'}
              </Box>
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="power-off"
            content={active ? 'Deactivate' : 'Activate'}
            disabled={!can_configure || (!active && !!disabledReason)}
            onClick={() => act('toggle')}
          />
          {!active && !!disabledReason && (
            <Box mt={1} color="bad">
              {disabledReason}
            </Box>
          )}
        </Section>
        <Section title="Guard">
          <LabeledList>
            <LabeledList.Item label="Preset">{preset_name || 'None set'}</LabeledList.Item>
            <LabeledList.Item label="Posted">
              {soldier_count} / {max_active_mobs}
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="user-cog"
            content="Set Preset"
            disabled={!can_configure}
            onClick={() => act('set_preset')}
          />
          <Button
            fluid
            mt={1}
            icon="user-slash"
            content="Dismiss Guard"
            disabled={!can_configure || soldier_count === 0}
            onClick={() => act('dismiss')}
          />
        </Section>
        <Section title="Facing">
          <Dropdown
            options={facing_options}
            displayText={facing}
            width="100%"
            selected={facing}
            disabled={!can_configure}
            onSelected={(value) => act('set_facing', { dir: value })}
          />
        </Section>
        <Section title="Hostility">
          <Button
            fluid
            mt={1}
            icon="crosshairs"
            content="Hostile"
            selected={hostility_mode === 'hostile'}
            disabled={!can_configure}
            onClick={() => act('set_hostile')}
          />
          <Button
            fluid
            mt={1}
            icon="hand-paper"
            content="Passive"
            selected={hostility_mode === 'passive'}
            disabled={!can_configure}
            onClick={() => act('set_passive')}
          />
        </Section>
      </Window.Content>
    </Window>
  );
};
