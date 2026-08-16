import { Box, Button, ProgressBar, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Product = {
  name: string;
  cost: number;
};

type Data = {
  prints_prosthetics: BooleanLike;
  stored_matter: number;
  max_stored_matter: number;
  print_job: string | null;
  print_seconds_left: number;
  print_delay_seconds: number;
  loaded_species_name: string | null;
  loaded_blood_type: string | null;
  loaded_blood_dna: string | null;
  products: Product[];
};

export const Bioprinter = (_props) => {
  const { act, data } = useBackend<Data>();
  const printsProsthetics = !!data.prints_prosthetics;
  const printing = !!data.print_job;
  const matterRatio =
    data.max_stored_matter > 0 ? data.stored_matter / data.max_stored_matter : 0;
  const matterColor =
    matterRatio > 0.5 ? 'good' : matterRatio > 0.2 ? 'average' : 'bad';

  return (
    <Window
      width={420}
      height={printsProsthetics ? 420 : 500}
      title={printsProsthetics ? 'Prosthetics Fabricator' : 'Organ Bioprinter'}
    >
      <Window.Content scrollable>
        <Section title="Stored Matter">
          <ProgressBar
            value={data.stored_matter}
            minValue={0}
            maxValue={data.max_stored_matter}
            ranges={{
              good: [data.max_stored_matter * 0.5, data.max_stored_matter],
              average: [data.max_stored_matter * 0.2, data.max_stored_matter * 0.5],
              bad: [0, data.max_stored_matter * 0.2],
            }}
          >
            {data.stored_matter} / {data.max_stored_matter}
          </ProgressBar>
          <Box mt={1} color="label">
            {printsProsthetics
              ? 'Feed it steel sheets to build up matter.'
              : 'Feed it meat to build up biomass.'}
          </Box>
        </Section>
        {!printsProsthetics && (
          <Section title="Loaded Sample">
            {data.loaded_species_name ? (
              <>
                <Box mb={1}>
                  Species:{' '}
                  <Box inline bold color="good">
                    {data.loaded_species_name}
                  </Box>
                </Box>
                <Box mb={1}>Blood Type: {data.loaded_blood_type || 'Unknown'}</Box>
                <Box color="label">DNA: {data.loaded_blood_dna || 'Unknown'}</Box>
              </>
            ) : (
              <Box color="average">
                No sample loaded -- inject a syringe holding a blood sample to
                identify a species and unlock its printable organs.
              </Box>
            )}
          </Section>
        )}
        <Section title="Printing">
          {printing ? (
            <>
              <Box mb={1}>
                Printing:{' '}
                <Box inline bold>
                  {data.print_job}
                </Box>
              </Box>
              <ProgressBar
                value={data.print_delay_seconds - data.print_seconds_left}
                minValue={0}
                maxValue={data.print_delay_seconds}
              >
                {data.print_seconds_left}s remaining
              </ProgressBar>
              <Button
                mt={1}
                fluid
                icon="times"
                color="bad"
                onClick={() => act('cancel')}
              >
                Cancel Print
              </Button>
            </>
          ) : (
            <Box color="label">Idle.</Box>
          )}
        </Section>
        <Section title="Printable Organs">
          {data.products.length === 0 && (
            <Box color="label">
              {printsProsthetics
                ? 'No printable prosthetics available.'
                : 'Load a blood sample to see this species’ printable organs.'}
            </Box>
          )}
          {data.products.map((product) => (
            <Button
              key={product.name}
              fluid
              mb={0.5}
              disabled={!!printing || data.stored_matter < product.cost}
              onClick={() => act('print', { choice: product.name })}
            >
              {product.name} ({product.cost} matter)
            </Button>
          ))}
        </Section>
      </Window.Content>
    </Window>
  );
};

export default Bioprinter;
