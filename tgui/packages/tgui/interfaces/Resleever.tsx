import { Box, Button, LabeledList, NoticeBox, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type ResleeverData = {
  lace_name: string | null;
  lace_occupied: BooleanLike;
  /** Name of the linked pod's occupant, but only when they're a valid
   * (mindless) resleeve target -- null if the pod is empty, still growing,
   * or already holds somebody with a mind of their own. */
  body_name: string | null;
  can_resleeve: BooleanLike;
  linked_pod: BooleanLike;
  pod_occupied: BooleanLike;
  pod_clone_name: string | null;
  pod_growing: BooleanLike;
  can_order_clone: BooleanLike;
  /** 0 when this server has cloning set to free (CLONING_COSTS_CREDITS). */
  clone_cost: number;
  clone_payer: string | null;
};

export const Resleever = (props) => {
  const { act, data } = useBackend<ResleeverData>();
  const {
    lace_name,
    lace_occupied,
    body_name,
    can_resleeve,
    linked_pod,
    pod_occupied,
    pod_clone_name,
    pod_growing,
    can_order_clone,
    clone_cost,
    clone_payer,
  } = data;

  return (
    <Window width={420} height={460} title="Resleeving Machine">
      <Window.Content scrollable>
        <Section title="Neural Lace">
          <LabeledList>
            <LabeledList.Item label="Inserted">
              {lace_name ? (
                <Box color={lace_occupied ? 'good' : 'average'}>
                  {lace_name} -- {lace_occupied ? 'consciousness present' : 'empty'}
                </Box>
              ) : (
                <Box color="label">No lace inserted.</Box>
              )}
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="eject"
            disabled={!lace_name}
            onClick={() => act('eject_lace')}
          >
            Eject Lace
          </Button>
        </Section>

        <Section title="Cloning Pod">
          {!linked_pod ? (
            <NoticeBox>
              No cloning pod linked. Use a multitool on the pod, then on this
              machine.
            </NoticeBox>
          ) : (
            <LabeledList>
              <LabeledList.Item label="Pod">
                {pod_growing ? (
                  <Box color="average">Growing...</Box>
                ) : pod_occupied ? (
                  <Box color={body_name ? 'good' : 'bad'}>
                    {body_name
                      ? `Clone ready: ${pod_clone_name}`
                      : `${pod_clone_name} (has a mind of their own -- not resleevable)`}
                  </Box>
                ) : (
                  <Box color="label">Empty.</Box>
                )}
              </LabeledList.Item>
              {clone_cost > 0 && (
                <LabeledList.Item label="Billed to">
                  {clone_payer}
                </LabeledList.Item>
              )}
            </LabeledList>
          )}
          <Button
            fluid
            mt={1}
            icon="dna"
            disabled={!can_order_clone}
            tooltip={
              !linked_pod
                ? 'No cloning pod linked.'
                : pod_growing
                  ? 'A clone is already growing.'
                  : pod_occupied
                    ? 'The linked pod already holds a body.'
                    : !lace_name
                      ? 'Insert the neural lace to clone from.'
                      : undefined
            }
            onClick={() => act('order_clone')}
          >
            {clone_cost > 0
              ? `Order Clone (${clone_cost.toLocaleString()} cr)`
              : 'Order Clone'}
          </Button>
        </Section>

        <Section title="Resleeve">
          <Button
            fluid
            icon="syringe"
            color="good"
            disabled={!can_resleeve}
            tooltip={
              !lace_name
                ? 'No lace inserted.'
                : !lace_occupied
                  ? 'That lace carries no consciousness.'
                  : !body_name
                    ? 'No resleevable body in the linked pod.'
                    : undefined
            }
            onClick={() => act('resleeve')}
          >
            Begin Resleeve
          </Button>
        </Section>
      </Window.Content>
    </Window>
  );
};
