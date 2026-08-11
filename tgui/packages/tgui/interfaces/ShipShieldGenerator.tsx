import { Box, Button, LabeledList, ProgressBar, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type ShipShieldGeneratorData = {
  active: BooleanLike;
  anchored: BooleanLike;
  linked: BooleanLike;
  shield_strength: number;
  max_shield_strength: number;
  sheets: number;
  max_sheets: number;
  sheet_name: string;
  seconds_per_sheet: number;
  seconds_remaining: number | null;
  recovery_seconds_left: number;
  at_away_site: BooleanLike;
  tractored: BooleanLike;
};

export const ShipShieldGenerator = (props) => {
  const { act, data } = useBackend<ShipShieldGeneratorData>();
  const {
    active,
    anchored,
    linked,
    shield_strength,
    max_shield_strength,
    sheets,
    max_sheets,
    sheet_name,
    seconds_per_sheet,
    seconds_remaining,
    recovery_seconds_left,
    at_away_site,
    tractored,
  } = data;

  const fuelRatio = max_sheets > 0 ? sheets / max_sheets : 0;
  const fuelColor =
    fuelRatio > 0.66 ? 'good' : fuelRatio > 0.33 ? 'average' : 'bad';

  const recovering = !active && recovery_seconds_left > 0;

  let disabledReason = '';
  if (recovering) {
    disabledReason = `Recalibrating after a shield collapse -- ready in ${recovery_seconds_left}s.`;
  } else if (!anchored) {
    disabledReason = 'Must be wrenched to the hull first.';
  } else if (!linked) {
    disabledReason = "Can't locate this ship on the overmap.";
  } else if (!active && sheets === 0) {
    disabledReason = `No ${sheet_name} loaded.`;
  } else if (!active && at_away_site) {
    disabledReason = "Shields can't be raised at an away site.";
  } else if (!active && tractored) {
    disabledReason = 'Held by an enemy tractor beam -- shields are locked out.';
  }

  return (
    <Window width={380} height={340} title="Shield Generator">
      <Window.Content scrollable>
        <Section title="Status">
          <Box mb={1}>
            Shields:{' '}
            <Box inline bold color={active ? 'good' : 'bad'}>
              {active ? 'ONLINE' : 'OFFLINE'}
            </Box>
          </Box>
          <Button
            fluid
            icon={active ? 'shield-alt' : 'shield'}
            content={active ? 'Deactivate' : 'Activate'}
            disabled={
              recovering ||
              !anchored ||
              (!active && sheets === 0) ||
              (!active && !!at_away_site) ||
              (!active && !!tractored)
            }
            tooltip={recovering ? disabledReason : undefined}
            onClick={() => act('toggle')}
          />
          {!!disabledReason && (
            <Box mt={1} color="bad">
              {disabledReason}
            </Box>
          )}
        </Section>
        <Section title="Shield Strength">
          <LabeledList>
            <LabeledList.Item label="Capacity">
              <ProgressBar
                ranges={{
                  good: [max_shield_strength * 0.5, max_shield_strength],
                  average: [max_shield_strength * 0.2, max_shield_strength * 0.5],
                  bad: [0, max_shield_strength * 0.2],
                }}
                value={shield_strength}
                minValue={0}
                maxValue={max_shield_strength}
              >
                {shield_strength} / {max_shield_strength}
              </ProgressBar>
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1} color="label">
            Regenerates gradually while online and fueled -- fuel only keeps
            the generator running, it doesn't affect shield strength or how
            fast it recovers.
          </Box>
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
