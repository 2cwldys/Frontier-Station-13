import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

export type MultitoolData = {
  tracking_apc: BooleanLike;
  selected_io: SelectedIo;
  buffer_name: string;
  airlock_checklist: AirlockChecklistItem[];
  chamber_pressure: number;
  has_exterior_sensor: BooleanLike;
  external_pressure: number;
  has_interior_sensor: BooleanLike;
  internal_pressure: number;
};

type SelectedIo = {
  name: string;
  type: string;
};

type AirlockChecklistItem = {
  label: string;
  linked: BooleanLike;
};

export const Multitool = (props) => {
  const { act, data } = useBackend<MultitoolData>();

  return (
    <Window>
      <Window.Content scrollable>
        <Section title="Smart Track">
          <Button
            disabled={!!data.selected_io}
            color={data.tracking_apc ? 'good' : ''}
            content={
              data.selected_io
                ? 'Toggle APC Smart Tracking (I/O in Buffer)'
                : 'Toggle APC Smart Tracking'
            }
            tooltip="Enabling this will update the multitool's icon to point in the direction of the nearest APC within your area."
            onClick={() => act('track_apc')}
          />
        </Section>
        <Section title="Buffer">
          <LabeledList>
            <LabeledList.Item label="Buffered">
              {data.buffer_name || 'Empty'}
            </LabeledList.Item>
          </LabeledList>
          <Button
            disabled={!data.buffer_name}
            content="Clear Buffer"
            icon="stop"
            onClick={() => act('clear_buffer')}
          />
        </Section>
        {data.airlock_checklist ? <AirlockChecklist /> : ''}
        {data.selected_io ? <IoWindow /> : ''}
      </Window.Content>
    </Window>
  );
};

export const AirlockChecklist = (props) => {
  const { data } = useBackend<MultitoolData>();
  return (
    <Section title="Airlock Controller Links">
      <LabeledList>
        {data.airlock_checklist.map((item) => (
          <LabeledList.Item key={item.label} label={item.label}>
            <Box color={item.linked ? 'good' : 'bad'}>
              {item.linked ? 'Linked' : 'Not Linked'}
            </Box>
          </LabeledList.Item>
        ))}
        <LabeledList.Item label="Chamber Pressure">
          {data.chamber_pressure} kPa
        </LabeledList.Item>
        {!!data.has_exterior_sensor && (
          <LabeledList.Item label="Exterior Pressure">
            {data.external_pressure} kPa
          </LabeledList.Item>
        )}
        {!!data.has_interior_sensor && (
          <LabeledList.Item label="Interior Pressure">
            {data.internal_pressure} kPa
          </LabeledList.Item>
        )}
      </LabeledList>
    </Section>
  );
};

export const IoWindow = (props) => {
  const { act, data } = useBackend<MultitoolData>();
  return (
    <Section title="Circuit I/O">
      <LabeledList>
        <LabeledList.Item label="I/O Name">
          {data.selected_io.name}
        </LabeledList.Item>
        <LabeledList.Item label="I/O Type">
          {data.selected_io.type}
        </LabeledList.Item>
      </LabeledList>
      <Button
        content="Clear I/O"
        icon="stop"
        tooltip="The I/O Buffer refers to the input/output wires of integrated circuits, which can be wired up using a multitool."
        onClick={() => act('clear_io')}
      />
    </Section>
  );
};
