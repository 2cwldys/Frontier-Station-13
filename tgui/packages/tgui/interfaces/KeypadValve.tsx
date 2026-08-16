import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type KeypadValveData = {
  valveName: string;
  codeSet: BooleanLike;
  open: BooleanLike;
  setterName: string;
  canReset: BooleanLike;
  entry: string;
};

const KEYPAD_ROWS: string[][] = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['C', '0', 'E'],
];

export const KeypadValve = (props) => {
  const { act, data } = useBackend<KeypadValveData>();

  return (
    <Window width={380} height={520}>
      <Window.Content scrollable>
        <Section title={data.valveName}>
          <LabeledList>
            <LabeledList.Item label="Valve">
              <Box color={data.open ? 'good' : 'bad'}>
                {data.open ? 'Open' : 'Closed'}
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Code">
              <Box color={data.codeSet ? 'good' : 'label'}>
                {data.codeSet ? 'Set' : 'Not Set'}
              </Box>
            </LabeledList.Item>
            {!!data.codeSet && (
              <LabeledList.Item label="Set By">
                {data.setterName || 'Unknown'}
              </LabeledList.Item>
            )}
          </LabeledList>
        </Section>

        <Section title={data.codeSet ? 'Enter Code' : 'Set a 5-Digit Code'}>
          <Box
            p={1}
            textAlign="center"
            style={{
              fontFamily: 'monospace',
              fontSize: '1.4em',
              backgroundColor: '#111',
              color: '#7f7',
              minHeight: '1.6em',
              border: '1px solid #333',
            }}
          >
            {'*'.repeat(data.entry?.length || 0) || ' '}
          </Box>
        </Section>

        <Section title="Keypad">
          {KEYPAD_ROWS.map((row, ri) => (
            <Stack key={ri} mb={0.5}>
              {row.map((key) => (
                <Stack.Item key={key} grow={1}>
                  <Button
                    fluid
                    textAlign="center"
                    content={key}
                    onClick={() => {
                      if (key === 'C') {
                        act('clear');
                      } else if (key === 'E') {
                        act('enter');
                      } else {
                        act('type', { value: key });
                      }
                    }}
                  />
                </Stack.Item>
              ))}
            </Stack>
          ))}
          {!!data.open && (
            <Button
              fluid
              mt={0.5}
              icon="faucet"
              content="Close Valve"
              color="caution"
              tooltip="Re-opening will need the code again."
              onClick={() => act('close_valve')}
            />
          )}
          {!!data.canReset && (
            <Button
              fluid
              mt={0.5}
              icon="undo"
              content="Reset Code"
              color="bad"
              onClick={() => act('reset_code')}
            />
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
