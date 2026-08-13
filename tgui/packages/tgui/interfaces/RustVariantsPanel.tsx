import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Data = {
  enabled: BooleanLike;
  wall_count: number;
  weathered_wall_count: number;
};

export const RustVariantsPanel = (_props) => {
  const { act, data } = useBackend<Data>();
  const enabled = !!data.enabled;
  const total = data.wall_count + data.weathered_wall_count;

  return (
    <Window width={420} height={340} title="Rust Variants Panel">
      <Window.Content scrollable>
        <Section title="Status">
          <Box mb={1}>
            Rust variants:{' '}
            <Box inline bold color={enabled ? 'bad' : 'good'}>
              {enabled ? 'RUSTY' : 'CLEAN'}
            </Box>
          </Box>
          <Button
            fluid
            icon={enabled ? 'toggle-on' : 'toggle-off'}
            content={enabled ? 'Switch All to Clean' : 'Switch All to Rusty'}
            color={enabled ? 'bad' : 'good'}
            onClick={() => act('toggle')}
          />
        </Section>
        <Section title="Tracked Instances">
          <LabeledList>
            <LabeledList.Item label="Dedicated Rust Walls">
              {data.wall_count}
            </LabeledList.Item>
            <LabeledList.Item label="Weathered Walls">
              {data.weathered_wall_count}
            </LabeledList.Item>
            <LabeledList.Item label="Total">
              <Box bold>{total}</Box>
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1} color="label">
            Dedicated Rust Walls are rare, map-placed instances only --
            normally-clean areas elsewhere are never touched. Weathered
            Walls is the real, pervasive effect: every
            currently-loaded steel/plasteel wall (station included) that
            draws from the per-tile weathering pool. Switching to Clean
            forces the unweathered sheet on all of them; switching back
            restores each wall&apos;s own natural look, not a random one.
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};

export default RustVariantsPanel;
