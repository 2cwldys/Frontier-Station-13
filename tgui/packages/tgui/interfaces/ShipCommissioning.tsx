import { useState } from 'react';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type ShipCommissioningData = {
  beacon_found: BooleanLike;
  beacon_label: string | null;
  beacon_link_broken: BooleanLike;
  footprint_x: number;
  footprint_y: number;
  price: number;
  own_faction: string | null;
  own_faction_name: string | null;
  envelope_occupied: BooleanLike;
  transponder_found: BooleanLike;
  transponder_link_broken: BooleanLike;
  transponder_aligned: BooleanLike;
  console_found: BooleanLike;
  console_link_broken: BooleanLike;
  propulsion_required: number;
  propulsion_count: number;
  propulsion_found: BooleanLike;
  helm_found: BooleanLike;
  navigation_found: BooleanLike;
  fuel_port_found: BooleanLike;
  engine_control_found: BooleanLike;
  ship_engine_found: BooleanLike;
  sensors_terminal_found: BooleanLike;
  sensor_array_found: BooleanLike;
  can_generate_floor: BooleanLike;
  is_admin: BooleanLike;
  admin_wipe_available: BooleanLike;
};

export const ShipCommissioning = (props) => {
  const { act, data } = useBackend<ShipCommissioningData>();
  const [dockAtBeacon, setDockAtBeacon] = useState(false);
  const commissionDisabled =
    !data.beacon_found ||
    !!data.envelope_occupied ||
    !data.transponder_found ||
    !data.transponder_aligned ||
    !data.console_found ||
    !data.propulsion_found ||
    !data.helm_found ||
    !data.fuel_port_found ||
    !data.engine_control_found ||
    !data.ship_engine_found ||
    !data.sensors_terminal_found ||
    !data.sensor_array_found;

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
          ) : data.beacon_link_broken ? (
            <Box color="bad">
              Linked beacon isn&apos;t valid right now -- deactivated,
              unanchored, or out of range. Reactivate it, or multitool a
              different beacon (Buffer), then multitool this console to
              link it.
            </Box>
          ) : (
            <Box color="bad">
              No beacon linked. Multitool a docking beacon, choose Buffer,
              then multitool this console to link it.
            </Box>
          )}
          <Button
            fluid
            mt={1}
            icon="unlink"
            color="bad"
            tooltip="Unlinks the beacon, transponder, and shuttle control console all at once, so you can start over."
            onClick={() => act('clear_links')}
          >
            Clear Links
          </Button>
        </Section>
        {!!data.beacon_found && !data.console_found && (
          <Section title="Shuttle Control Console Required">
            <Box color="bad">
              {data.console_link_broken
                ? "Linked shuttle control console isn't inside the build envelope -- move it, or link a different one."
                : 'No shuttle control console linked -- without one, this hull could never be flown once commissioned. Multitool one, choose Buffer, then multitool this console to link it.'}
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !data.transponder_found && (
          <Section title="Docking Transponder Required">
            <Box color="bad">
              {data.transponder_link_broken
                ? "Linked docking transponder isn't inside the build envelope -- move it, or link a different one."
                : 'No docking transponder linked -- mount one at your airlock, multitool it, choose Buffer, then multitool this console to link it. It needs to face the beacon.'}
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !!data.transponder_found && !data.transponder_aligned && (
          <Section title="Docking Transponder Misaligned">
            <Box color="bad">
              The transponder isn&apos;t facing the beacon -- rotate either
              one (multitool) until they face each other.
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !data.propulsion_found && (
          <Section title="Propulsion Engines Required">
            <Box color="bad">
              Only {data.propulsion_count} of {data.propulsion_required}{' '}
              required propulsion engines found in the build envelope --
              cargo-order more (Propulsion Engine Crate) and wrench them
              down anywhere inside the hull.
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !data.helm_found && (
          <Section title="Helm Console Required">
            <Box color="bad">
              No helm console found in the build envelope -- without one,
              this hull could never actually be piloted on the overmap.
              Cargo-order one (Helm Console Crate) and wrench it down
              anywhere inside the hull.
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !data.fuel_port_found && (
          <Section title="Fuel Port Required">
            <Box color="bad">
              No fuel port found in the build envelope -- without one, this
              hull could never be refuelled. Cargo-order one (Fuel Port
              Crate) and attach it to a wall anywhere inside the hull.
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !data.engine_control_found && (
          <Section title="Engine Control Terminal Required">
            <Box color="bad">
              No engine control terminal found in the build envelope --
              without one, this hull's engines could never actually be
              turned on. Cargo-order one (Engine Control Terminal Crate) and
              wrench it down anywhere inside the hull.
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !data.ship_engine_found && (
          <Section title="Engine Required">
            <Box color="bad">
              No engine found in the build envelope -- the decorative
              propulsion units alone don't actually burn fuel. Cargo-order
              either a Ship Nozzle Engine Crate (wrench it down and pipe it
              into a fuel-gas network -- any gas canister works, not just
              phoron) or an Ion Engine Crate (wrench it down and wire it to
              power -- no piping needed at all). Either one satisfies this
              requirement; you don't need both.
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !data.sensors_terminal_found && (
          <Section title="Sensors Terminal Required">
            <Box color="bad">
              No sensors terminal found in the build envelope -- without one,
              crew have no way to see anything outside the hull. Cargo-order
              one (Sensors Terminal Crate) and wrench it down anywhere inside
              the hull.
            </Box>
          </Section>
        )}
        {!!data.beacon_found && !data.sensor_array_found && (
          <Section title="Sensor Array Required">
            <Box color="bad">
              No sensor array found in the build envelope -- the sensors
              terminal has nothing to actually read from without one.
              Cargo-order one (Ship Sensor Array Crate) and wrench it down
              anywhere inside the hull.
            </Box>
          </Section>
        )}
        {!!data.envelope_occupied && (
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
            <LabeledList.Item label="Build Size">
              {data.footprint_x} x {data.footprint_y} tiles
            </LabeledList.Item>
            <LabeledList.Item label="Commission Fee">
              {data.price} credits
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="ruler-combined"
            tooltip="Changes the build envelope size for this console -- preview again afterward."
            onClick={() => act('set_build_size')}
          >
            Set Build Size
          </Button>
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
        {!!data.is_admin && (
          <Section title="Administration">
            <Button
              fluid
              icon="eraser"
              color="bad"
              disabled={!data.admin_wipe_available}
              tooltip={
                data.admin_wipe_available
                  ? "Wipes this console's whole build envelope back to open space and forgets its saved turf/object rows, so nothing rebuilds there on the next boot. Works even if the beacon is deactivated."
                  : 'No beacon linked to this console (or it is on another z) -- there is no envelope to define. Link one first.'
              }
              onClick={() => act('admin_wipe_envelope')}
            >
              Wipe Build Envelope (Admin)
            </Button>
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};
