import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type KeypadDoorData = {
  doorName: string;
  codeSet: BooleanLike;
  locked: BooleanLike;
  doorOpen: BooleanLike;
  setterName: string;
  canReset: BooleanLike;
  isAdmin: BooleanLike;
  canHoldOpen: BooleanLike;
  entry: string;
  adminForcedOpen: BooleanLike;
};

const KEYPAD_ROWS: string[][] = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['C', '0', 'E'],
];

export const KeypadDoor = (props) => {
  const { act, data } = useBackend<KeypadDoorData>();

  return (
    <Window width={380} height={650}>
      <Window.Content scrollable>
        <Section title={data.doorName}>
          <LabeledList>
            <LabeledList.Item label="Status">
              {data.adminForcedOpen ? (
                <Box color="caution">Bolted Open (Admin)</Box>
              ) : (
                <Box color={data.locked ? 'bad' : 'good'}>
                  {data.locked ? 'Locked' : 'Unlocked'}
                </Box>
              )}
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
          {!!data.doorOpen && (
            <Button
              fluid
              mt={0.5}
              icon="door-closed"
              content="Close Door"
              onClick={() => act('close_door')}
            />
          )}
          {!!data.doorOpen && (
            <Button
              fluid
              mt={0.5}
              icon={data.adminForcedOpen ? 'unlock' : 'thumbtack'}
              color={data.adminForcedOpen ? 'bad' : undefined}
              content={
                data.adminForcedOpen ? 'Release Forced Open' : 'Force Open'
              }
              tooltip={
                data.adminForcedOpen
                  ? 'Let the door close and re-lock on its own again.'
                  : 'Hold the door open indefinitely.'
              }
              onClick={() => act('force_open')}
            />
          )}
        </Section>

        {(!!data.canReset || !!data.isAdmin || !!data.canHoldOpen) && (
          <Section title="Administration">
            {!!data.canReset && (
              <Button
                fluid
                icon="undo"
                content="Reset Code"
                color="bad"
                onClick={() => act('reset_code')}
              />
            )}
            {!!data.isAdmin && (
              <Button
                fluid
                icon="unlock"
                content="Force Unlock"
                color="caution"
                onClick={() => act('force_unlock')}
              />
            )}
            {!!data.canHoldOpen && !data.adminForcedOpen && (
              <Button
                fluid
                icon="door-open"
                content="Bolt Open"
                color="caution"
                onClick={() => act('bolt_open')}
              />
            )}
            {!!data.canHoldOpen && !!data.adminForcedOpen && (
              <Button
                fluid
                icon="undo"
                content="Return to Default"
                color="good"
                onClick={() => act('restore_default')}
              />
            )}
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};
