import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type ShipCloakingDeviceData = {
  active: BooleanLike;
  anchored: BooleanLike;
  linked: BooleanLike;
  sheets: number;
  max_sheets: number;
  sheet_name: string;
  seconds_per_sheet: number;
  seconds_remaining: number | null;
  at_away_site: BooleanLike;
};

export const ShipCloakingDevice = (props) => {
  const { act, data } = useBackend<ShipCloakingDeviceData>();
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
  } = data;

  const fuelRatio = max_sheets > 0 ? sheets / max_sheets : 0;
  const fuelColor =
    fuelRatio > 0.66 ? 'good' : fuelRatio > 0.33 ? 'average' : 'bad';

  let disabledReason = '';
  if (!anchored) {
    disabledReason = 'Must be wrenched to the hull first.';
  } else if (!linked) {
    disabledReason = "Can't locate this ship on the overmap.";
  } else if (!active && sheets === 0) {
    disabledReason = `No ${sheet_name} loaded.`;
  } else if (!active && at_away_site) {
    disabledReason = "Can't cloak the ship at an away site.";
  }

  return (
    <Window width={380} height={320} title="Cloaking Device">
      <Window.Content scrollable>
        <Section title="Status">
          <Box mb={1}>
            Cloak:{' '}
            <Box inline bold color={active ? 'good' : 'bad'}>
              {active ? 'ACTIVE -- undetectable' : 'OFFLINE'}
            </Box>
          </Box>
          <Button
            fluid
            icon={active ? 'eye-slash' : 'eye'}
            content={active ? 'Deactivate' : 'Activate'}
            disabled={
              !anchored ||
              (!active && sheets === 0) ||
              (!active && !!at_away_site)
            }
            onClick={() => act('toggle')}
          />
          {!!disabledReason && (
            <Box mt={1} color="bad">
              {disabledReason}
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
                <Box color={seconds_remaining < seconds_per_sheet * 3 ? 'bad' : 'label'}>
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
