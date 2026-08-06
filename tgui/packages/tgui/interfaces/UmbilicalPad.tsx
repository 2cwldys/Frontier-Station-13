import { Box, Button, LabeledList, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type LinkedPad = {
  ref: string;
  name: string;
  location: string;
};

type UmbilicalPadData = {
  link_code: string;
  enabled: BooleanLike;
  connected: BooleanLike;
  linked_pads: LinkedPad[];
};

export const UmbilicalPad = (props) => {
  const { act, data } = useBackend<UmbilicalPadData>();

  return (
    <Window width={400} height={340}>
      <Window.Content scrollable>
        <Section title="Access Code">
          <LabeledList>
            <LabeledList.Item label="Current Code">
              {data.link_code || 'None set'}
              <Button ml={1} onClick={() => act('set_code')}>
                Set Code
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Status">
              {data.enabled ? (
                <Box inline color={data.connected ? 'good' : 'label'}>
                  {data.connected ? 'Connected' : 'Enabled, no partner'}
                </Box>
              ) : (
                <Box inline color="bad">
                  Disabled
                </Box>
              )}
              <Button ml={1} onClick={() => act('toggle_enabled')}>
                {data.enabled ? 'Disable' : 'Enable'}
              </Button>
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section title="Matching Pads">
          {data.linked_pads.length ? (
            <Table>
              {data.linked_pads.map((pad) => (
                <Table.Row key={pad.ref}>
                  <Table.Cell>{pad.name}</Table.Cell>
                  <Table.Cell color="label">{pad.location}</Table.Cell>
                </Table.Row>
              ))}
            </Table>
          ) : (
            <Box color="label">
              {data.link_code
                ? 'No other pad currently shares this code.'
                : 'Set an access code to tether to another pad.'}
            </Box>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
