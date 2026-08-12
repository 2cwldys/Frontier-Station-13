import { Box, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type ShipTractorBeamData = {
  active: BooleanLike;
  anchored: BooleanLike;
  linked: BooleanLike;
  sheets: number;
  max_sheets: number;
  sheet_name: string;
  seconds_per_sheet: number;
  seconds_remaining: number | null;
  at_away_site: BooleanLike;
  locked_target_name: string | null;
  has_console_target: BooleanLike;
};

export const ShipTractorBeam = (props) => {
  const { data } = useBackend<ShipTractorBeamData>();
  const {
    active,
    anchored,
    linked,
    sheets,
    max_sheets,
    sheet_name,
    seconds_per_sheet,
    seconds_remaining,
    at_away_site,
    locked_target_name,
    has_console_target,
  } = data;

  const fuelRatio = max_sheets > 0 ? sheets / max_sheets : 0;
  const fuelColor =
    fuelRatio > 0.66 ? 'good' : fuelRatio > 0.33 ? 'average' : 'bad';

  let statusNote = '';
  if (!anchored) {
    statusNote = 'Must be wrenched to the hull first.';
  } else if (!linked) {
    statusNote = "Can't locate this ship on the overmap.";
  } else if (!active && sheets === 0) {
    statusNote = `No ${sheet_name} loaded.`;
  } else if (!active && at_away_site) {
    statusNote = "Can't lock onto anything at an away site.";
  } else if (!active && !has_console_target) {
    statusNote = 'No target locked on the gunnery console.';
  }

  return (
    <Window width={380} height={360} title="Tractor Beam Projector">
      <Window.Content scrollable>
        <Section title="Status">
          <Box mb={1}>
            Field:{' '}
            <Box inline bold color={active ? 'good' : 'bad'}>
              {active ? 'ACTIVE -- locked on' : 'OFFLINE'}
            </Box>
          </Box>
          {!!active && (
            <Box mb={1}>
              Holding:{' '}
              <Box inline bold color="danger">
                {locked_target_name || 'Unknown contact'}
              </Box>
            </Box>
          )}
          <Box color="label">
            Activated and released from the ship's gunnery console.
          </Box>
          {!!statusNote && (
            <Box mt={1} color="bad">
              {statusNote}
            </Box>
          )}
        </Section>
        <Section title="Fuel Reserve">
          <Box mb={1}>
            Reserve:{' '}
            <Box inline bold color={fuelColor}>
              {sheets} / {max_sheets} {sheet_name}
            </Box>
          </Box>
          <LabeledList>
            <LabeledList.Item label="Consumption">
              1 {sheet_name} every {seconds_per_sheet}s while active
            </LabeledList.Item>
            {!!active && seconds_remaining !== null && (
              <LabeledList.Item label="Time Remaining">
                <Box
                  color={
                    seconds_remaining < seconds_per_sheet * 3
                      ? 'bad'
                      : 'label'
                  }
                >
                  {seconds_remaining}s
                </Box>
              </LabeledList.Item>
            )}
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
