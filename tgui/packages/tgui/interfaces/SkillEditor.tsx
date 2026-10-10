import { useState } from 'react';
import { Box, Button, Dropdown, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type SkillOption = {
  level: number;
  name: string;
};

type Skill = {
  type: string;
  name: string;
  level: number;
  level_name: string;
  options: SkillOption[];
};

type SkillEditorData = {
  ckey: string;
  char_name: string;
  is_live: BooleanLike;
  skills: Skill[];
};

type SkillRowProps = {
  skill: Skill;
  selected: number;
  onSelected: (type: string, level: number) => void;
};

const SkillRow = (props: SkillRowProps) => {
  const { skill, selected, onSelected } = props;
  const changed = selected !== skill.level;
  return (
    <Table.Row>
      <Table.Cell bold={changed}>{skill.name}</Table.Cell>
      <Table.Cell color="label">{skill.level_name}</Table.Cell>
      <Table.Cell>
        <Dropdown
          width="12rem"
          selected={selected}
          displayText={
            skill.options.find((o) => o.level === selected)?.name ?? ''
          }
          options={skill.options.map((o) => ({
            value: o.level,
            displayText: o.name,
          }))}
          onSelected={(value) => onSelected(skill.type, Number(value))}
        />
      </Table.Cell>
    </Table.Row>
  );
};

export const SkillEditor = (_props) => {
  const { act, data } = useBackend<SkillEditorData>();
  const { ckey, char_name, is_live, skills = [] } = data;
  const [selections, setSelections] = useState<Record<string, number>>({});

  const getSelected = (skill: Skill) =>
    selections[skill.type] ?? skill.level;

  const changedCount = skills.filter(
    (skill) => getSelected(skill) !== skill.level,
  ).length;

  return (
    <Window width={480} height={640} title="Modify Skills">
      <Window.Content scrollable>
        <Section title="Target">
          <Box>
            <Box inline bold>
              {char_name}
            </Box>{' '}
            ({ckey}) --{' '}
            <Box inline color={is_live ? 'good' : 'label'}>
              {is_live ? 'currently playing' : 'offline'}
            </Box>
          </Box>
        </Section>
        <Section
          title="Skills"
          buttons={
            <Button
              icon="save"
              content={`Apply Changes (${changedCount})`}
              disabled={!changedCount}
              color={changedCount ? 'good' : undefined}
              onClick={() => {
                act('apply', { changes: selections });
                setSelections({});
              }}
            />
          }
        >
          <Table>
            <Table.Row header>
              <Table.Cell>Skill</Table.Cell>
              <Table.Cell>Current</Table.Cell>
              <Table.Cell>Set To</Table.Cell>
            </Table.Row>
            {skills.map((skill) => (
              <SkillRow
                key={skill.type}
                skill={skill}
                selected={getSelected(skill)}
                onSelected={(type, level) =>
                  setSelections((prev) => ({ ...prev, [type]: level }))
                }
              />
            ))}
          </Table>
        </Section>
      </Window.Content>
    </Window>
  );
};

export default SkillEditor;
