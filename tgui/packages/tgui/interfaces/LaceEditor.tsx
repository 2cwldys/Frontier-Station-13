import { useState } from 'react';
import { Box, Button, Dropdown, Input, LabeledList, Section } from 'tgui-core/components';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type LaceEditorData = {
  ckey: string;
  char_name: string;
  species_override: string;
  original_species: string;
  species_options: string[];
  lace_status: string | null;
  lace_damage: number | null;
  owner_faction: string | null;
};

const USE_DEFAULT = '__use_default__';

export const LaceEditor = (_props) => {
  const { act, data } = useBackend<LaceEditorData>();
  const {
    ckey,
    char_name,
    species_override,
    original_species,
    species_options = [],
    lace_status,
    lace_damage,
    owner_faction,
  } = data;

  const [override, setOverride] = useState<string | null>(null);
  const [damage, setDamage] = useState<string | null>(null);
  const [faction, setFaction] = useState<string | null>(null);

  const currentOverride = override ?? species_override;
  const currentDamage = damage ?? (lace_damage === null ? '' : String(lace_damage));
  const currentFaction = faction ?? (owner_faction || '');

  const changed =
    currentOverride !== species_override ||
    (lace_status !== null && currentDamage !== String(lace_damage ?? '')) ||
    (lace_status !== null && currentFaction !== (owner_faction || ''));

  return (
    <Window width={480} height={520} title="Modify Neural Lace">
      <Window.Content scrollable>
        <Section title="Target">
          <Box>
            <Box inline bold>
              {char_name}
            </Box>{' '}
            ({ckey})
          </Box>
        </Section>
        <Section title="Cloning">
          <LabeledList>
            <LabeledList.Item label="Species Override">
              <Dropdown
                width="14rem"
                selected={currentOverride || USE_DEFAULT}
                displayText={currentOverride || 'Use character default'}
                options={[
                  { value: USE_DEFAULT, displayText: 'Use character default' },
                  ...species_options.map((name) => ({
                    value: name,
                    displayText: name,
                  })),
                ]}
                onSelected={(value) =>
                  setOverride(value === USE_DEFAULT ? '' : value)
                }
              />
            </LabeledList.Item>
          </LabeledList>
          <Box color="label" mt={1}>
            When set, the next clone grown of this character comes out as
            this species instead of their own chargen preference. Clearing
            it back to "Use character default" reverts to their normal
            species.
          </Box>
          {!!original_species && (
            <Box mt={1}>
              <Box color="label" inline>
                Chargen species before their last resleeve:{' '}
              </Box>
              <Box inline bold>
                {original_species}
              </Box>
              <Button
                ml={1}
                icon="undo"
                content="Restore Original Species"
                color="caution"
                onClick={() => act('restore_original_species')}
              />
            </Box>
          )}
        </Section>
        <Section title="Physical Lace">
          {lace_status === null ? (
            <Box color="label">No physical lace found for this character.</Box>
          ) : (
            <LabeledList>
              <LabeledList.Item label="Status">{lace_status}</LabeledList.Item>
              <LabeledList.Item label="Damage">
                <Input
                  width="5rem"
                  value={currentDamage}
                  onChange={(value) => setDamage(value)}
                />
                {' / 100'}
              </LabeledList.Item>
              <LabeledList.Item label="Owner Faction">
                <Input
                  width="14rem"
                  value={currentFaction}
                  placeholder="(none)"
                  onChange={(value) => setFaction(value)}
                />
              </LabeledList.Item>
            </LabeledList>
          )}
        </Section>
        <Section>
          <Button
            fluid
            icon="save"
            content="Apply Changes"
            disabled={!changed}
            color={changed ? 'good' : undefined}
            onClick={() => {
              act('apply', {
                species_override: currentOverride,
                ...(lace_status !== null
                  ? { lace_damage: currentDamage, owner_faction: currentFaction }
                  : {}),
              });
              setOverride(null);
              setDamage(null);
              setFaction(null);
            }}
          />
        </Section>
      </Window.Content>
    </Window>
  );
};

export default LaceEditor;
