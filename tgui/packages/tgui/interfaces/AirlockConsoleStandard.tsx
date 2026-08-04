import {
  Box,
  Button,
  LabeledList,
  ProgressBar,
  Section,
} from 'tgui-core/components';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type AirlockDiagnostics = {
  state: string;
  target_state: string;
  chamber_pressure: number;
  external_pressure: number;
  internal_pressure: number;
  pump_status: string;
  pump_condition: string;
  tag_exterior_door: string;
  tag_interior_door: string;
  tag_airpump: string;
  tag_chamber_sensor: string;
  tag_exterior_sensor: string;
  tag_interior_sensor: string;
};

export type StandardAirlockConsoleData = {
  chamber_pressure: number;
  processing: boolean;
  diagnostics: AirlockDiagnostics;
};

export const AirlockConsoleStandard = (props) => {
  const { act, data } = useBackend<StandardAirlockConsoleData>();
  const { diagnostics } = data;

  return (
    <Window>
      <Window.Content scrollable>
        <Section title="Status">
          <Box>
            <LabeledList>
              <LabeledList.Item label="Chamber Pressure">
                <ProgressBar
                  ranges={{
                    average: [120, Infinity],
                    good: [80, 120],
                    bad: [-Infinity, 80],
                  }}
                  value={data.chamber_pressure}
                  minValue={0}
                  maxValue={200}
                >
                  {data.chamber_pressure} kPa
                </ProgressBar>
              </LabeledList.Item>
            </LabeledList>
          </Box>
        </Section>
        {!!diagnostics && (
          <Section title="Diagnostics">
            <LabeledList>
              <LabeledList.Item label="Cycle State">
                {diagnostics.state}
              </LabeledList.Item>
              <LabeledList.Item label="Target">
                {diagnostics.target_state}
              </LabeledList.Item>
              <LabeledList.Item label="Chamber / External / Internal">
                {diagnostics.chamber_pressure} kPa /{' '}
                {diagnostics.external_pressure} kPa /{' '}
                {diagnostics.internal_pressure} kPa
              </LabeledList.Item>
              <LabeledList.Item label="Pump Status">
                {diagnostics.pump_status}
              </LabeledList.Item>
              <LabeledList.Item label="Pump Condition">
                {diagnostics.pump_condition}
              </LabeledList.Item>
              <LabeledList.Item label="Exterior Door Tag">
                {diagnostics.tag_exterior_door}
              </LabeledList.Item>
              <LabeledList.Item label="Interior Door Tag">
                {diagnostics.tag_interior_door}
              </LabeledList.Item>
              <LabeledList.Item label="Airpump Tag">
                {diagnostics.tag_airpump}
              </LabeledList.Item>
              <LabeledList.Item label="Chamber Sensor Tag">
                {diagnostics.tag_chamber_sensor}
              </LabeledList.Item>
              <LabeledList.Item label="Exterior Sensor Tag">
                {diagnostics.tag_exterior_sensor}
              </LabeledList.Item>
              <LabeledList.Item label="Interior Sensor Tag">
                {diagnostics.tag_interior_sensor}
              </LabeledList.Item>
            </LabeledList>
          </Section>
        )}
        <Section title="Controls">
          <Box>
            <Button
              content="Cycle to Exterior"
              icon="arrow-right-from-bracket"
              onClick={() => act('command', { command: 'cycle_ext' })}
            />
            <Button
              content="Cycle to Interior"
              icon="arrow-right-to-bracket"
              onClick={() => act('command', { command: 'cycle_int' })}
            />
            <Button
              content="Cancel Cycling"
              icon="ban"
              color="red"
              disabled={!data.processing}
              onClick={() => act('command', { command: 'abort' })}
            />
          </Box>
          <Box>
            <Button
              content="Force Exterior Door"
              icon="circle-exclamation"
              color="yellow"
              onClick={() => act('command', { command: 'force_ext' })}
            />
            <Button
              content="Force Interior Door"
              icon="circle-exclamation"
              color="yellow"
              onClick={() => act('command', { command: 'force_int' })}
            />
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
