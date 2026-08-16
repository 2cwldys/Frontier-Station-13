import { Box, Button, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Data = {
  powered: BooleanLike;
  operational: BooleanLike;
  tethered: BooleanLike;
  fuel_credits: number;
  max_fuel_credits: number;
  founding_cost: number;
  claimed_faction_name: string | null;
};

export const PiracyBeacon = (_props) => {
  const { act, data } = useBackend<Data>();
  const powered = !!data.powered;
  const operational = !!data.operational;
  const tethered = !!data.tethered;
  const fuelRatio =
    data.max_fuel_credits > 0 ? data.fuel_credits / data.max_fuel_credits : 0;
  const fuelColor =
    fuelRatio > 0.66 ? 'good' : fuelRatio > 0.33 ? 'average' : 'bad';

  return (
    <Window width={400} height={460} title="Piracy Beacon">
      <Window.Content scrollable>
        <Section title="Status">
          <Box mb={1}>
            Power:{' '}
            <Box inline bold color={powered ? 'good' : 'average'}>
              {powered ? 'On' : 'Off'}
            </Box>
          </Box>
          <Box mb={1}>
            Synced:{' '}
            <Box inline bold color={operational ? 'good' : 'average'}>
              {operational ? 'Yes' : 'No'}
            </Box>
            {powered && !operational && (
              <Box inline color="label">
                {' '}
                (powered, but this space is too regulated right now)
              </Box>
            )}
          </Box>
          <Box mb={1}>
            Persistence:{' '}
            <Box inline bold color={tethered ? 'good' : 'average'}>
              {tethered ? 'Tethered' : 'Untethered'}
            </Box>
          </Box>
          <Box mb={1} color="label">
            Tethering is independent of power -- it decides whether this Z's
            contents survive a restart. It has no effect on whether the
            beacon itself is otherwise functioning.
          </Box>
          <Box mb={1}>
            Territory:{' '}
            {data.claimed_faction_name ? (
              <Box inline bold color="good">
                Claimed by {data.claimed_faction_name}
              </Box>
            ) : (
              <Box inline bold color="average">
                Unclaimed
              </Box>
            )}
          </Box>
          <Box mb={1} color="label">
            While tethered, a faction can claim this Z with a Faction Tagger,
            exactly like a faction beacon -- raiding it is then blocked while
            the server's raiding toggle is off, and gunnery can't lock onto
            or bombard it, both exempting the claiming faction's own members.
            Unlike a real faction beacon, this never raises the Z's security
            tier or shows a shield on the overmap -- it stays hidden.
          </Box>
          <Box mb={1}>
            Fuel Reserve:{' '}
            <Box inline bold color={fuelColor}>
              {data.fuel_credits} / {data.max_fuel_credits} cr
            </Box>
          </Box>
          <Box mb={1} color="label">
            Insert credit chips to add fuel; alt-click to withdraw.
          </Box>
          <Box mt={1}>
            <Button
              icon="power-off"
              color={powered ? 'bad' : 'good'}
              onClick={() => act('toggle_power')}
            >
              {powered ? 'Power Off' : 'Power On'}
            </Button>
            <Button
              icon="anchor"
              color={tethered ? 'bad' : 'good'}
              onClick={() => act('toggle_tether')}
            >
              {tethered ? 'Untether' : 'Tether'} This Z
            </Button>
          </Box>
        </Section>
        <Section title="Found a Pirate Faction">
          <Box mb={1} color="label">
            Pay {data.founding_cost.toLocaleString()} credits, held as physical
            cash in hand,
            to instantly found a real faction here -- no petition, no
            supporters, no waiting. It gets full faction management support
            (ranks, a bank account seeded with the payment, a master card),
            but it can never import cargo of any kind and can never be
            listed on any stock exchange. Its only economy is theft and
            illegal exports -- which already work from any of its own
            consoles parked on a powered piracy beacon's Z.
          </Box>
          <Button
            icon="flag"
            color="bad"
            onClick={() => act('found_faction')}
          >
            Found Faction ({data.founding_cost.toLocaleString()} cr)
          </Button>
        </Section>
      </Window.Content>
    </Window>
  );
};

export default PiracyBeacon;
