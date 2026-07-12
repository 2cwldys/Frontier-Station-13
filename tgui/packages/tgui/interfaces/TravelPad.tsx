import { Box, Button, LabeledList, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type LinkedPad = {
  ref: string;
  name: string;
  location: string;
};

type TravelPadData = {
  link_code: string;
  linked_pads: LinkedPad[];
  can_travel: BooleanLike;
  cooldown: number;
};

export const TravelPad = (props) => {
  const { act, data } = useBackend<TravelPadData>();

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
          </LabeledList>
        </Section>
        <Section title="Linked Pads">
          {data.linked_pads.length ? (
            <Table>
              {data.linked_pads.map((pad) => (
                <Table.Row key={pad.ref}>
                  <Table.Cell>{pad.name}</Table.Cell>
                  <Table.Cell color="label">{pad.location}</Table.Cell>
                  <Table.Cell collapsing>
                    <Button
                      disabled={!data.can_travel}
                      onClick={() => act('travel', { target: pad.ref })}
                    >
                      {data.can_travel
                        ? 'Travel'
                        : `Recalibrating (${data.cooldown}s)`}
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          ) : (
            <Box color="label">
              {data.link_code
                ? 'No other pad currently shares this code.'
                : 'Set an access code to see linked pads.'}
            </Box>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
