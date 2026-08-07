import { useState } from 'react';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type ShipCommissioningData = {
  beacon_found: BooleanLike;
  beacon_label: string | null;
  footprint_x: number;
  footprint_y: number;
  price: number;
  own_faction: string | null;
  own_faction_name: string | null;
  envelope_occupied: BooleanLike;
  transponder_found: BooleanLike;
  transponder_aligned: BooleanLike;
  console_found: BooleanLike;
  can_generate_floor: BooleanLike;
};

export const ShipCommissioning = (props) => {
  const { act, data } = useBackend<ShipCommissioningData>();
  const [dockAtBeacon, setDockAtBeacon] = useState(false);
  const commissionDisabled =
    !data.beacon_found ||
    !!data.envelope_occupied ||
    !data.transponder_found ||
    !data.transponder_aligned ||
    !data.console_found;

  return (
    <Window width={420} height={460}>
      <Window.Content scrollable>
        <Section title="Linked Docking Beacon">
          {data.beacon_found ? (
            <Box color="good">
              Linked to &quot;{data.beacon_label}&quot; -- the build envelope
              extends out from it in whichever direction it's currently
              facing.
            </Box>
          ) : (
            <Box color="bad">
              No active docking beacon in range. Place and activate one
              first.
            </Box>
          )}
        </Section>
        {data.beacon_found && !data.console_found && (
          <Section title="Shuttle Control Console Required">
            <Box color="bad">
              No shuttle control console found in the build envelope --
              without one, this hull could never be flown once commissioned.
            </Box>
          </Section>
        )}
        {data.beacon_found && !data.transponder_found && (
          <Section title="Docking Transponder Required">
            <Box color="bad">
              No docking transponder found in the build envelope -- mount
              one at your airlock and rotate it (multitool) to face away
              from the beacon.
            </Box>
          </Section>
        )}
        {data.beacon_found && data.transponder_found && !data.transponder_aligned && (
          <Section title="Docking Transponder Misaligned">
            <Box color="bad">
              The transponder isn&apos;t facing the beacon -- rotate either
              one (multitool) until they face each other.
            </Box>
          </Section>
        )}
        {data.envelope_occupied && (
          <Section title="Build Envelope Occupied">
            <Box color="bad">
              Someone (or something&apos;s remains) is still inside the
              build envelope -- they need to move off before you can
              commission.
            </Box>
          </Section>
        )}
        <Section title="Build Envelope">
          <LabeledList>
            <LabeledList.Item label="Max Size">
              {data.footprint_x} x {data.footprint_y} tiles
            </LabeledList.Item>
            <LabeledList.Item label="Commission Fee">
              {data.price} credits
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="border-all"
            disabled={!data.beacon_found}
            onClick={() => act('preview')}
          >
            Preview Build Envelope
          </Button>
          <Button
            fluid
            mt={1}
            icon="th"
            disabled={!data.can_generate_floor}
            tooltip={
              data.can_generate_floor
                ? 'Fills any open-space tiles in the envelope with plating -- never touches anything already built.'
                : 'Preview the envelope first -- only available when it comes back clear of walls, objects, and mobs.'
            }
            onClick={() => act('generate_floor')}
          >
            Generate Build Floor
          </Button>
        </Section>
        <Section title="Commission">
          <LabeledList>
            <LabeledList.Item label="On Deployment">
              <Button.Checkbox
                checked={dockAtBeacon}
                onClick={() => setDockAtBeacon(!dockAtBeacon)}
              >
                {dockAtBeacon
                  ? 'Stay docked at the beacon'
                  : 'Launch into nearby open space'}
              </Button.Checkbox>
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="file-signature"
            disabled={commissionDisabled}
            onClick={() =>
              act('commission', {
                as_faction: false,
                dock_at_beacon: dockAtBeacon,
              })
            }
          >
            Commission (Personal Account)
          </Button>
          {data.own_faction && (
            <Button
              fluid
              mt={1}
              icon="flag"
              disabled={commissionDisabled}
              onClick={() =>
                act('commission', {
                  as_faction: true,
                  dock_at_beacon: dockAtBeacon,
                })
              }
            >
              Commission for {data.own_faction_name}
            </Button>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
