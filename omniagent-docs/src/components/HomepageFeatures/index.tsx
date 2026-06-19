import type {ReactNode} from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  icon: string;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'Convention Over Configuration',
    icon: '🛤️',
    description: (
      <>
        Opinionated, Rails-style generators scaffold agents, tools, and
        prompts so you can start shipping instead of wiring plumbing.
      </>
    ),
  },
  {
    title: 'Provider-Agnostic',
    icon: '🔌',
    description: (
      <>
        Swap providers and models per agent with <code>provider</code> or{' '}
        <code>use_model</code>. OpenAI ships out of the box, with more on the
        way.
      </>
    ),
  },
  {
    title: 'Tools Built In',
    icon: '🛠️',
    description: (
      <>
        Define tools with a JSON-schema-style DSL and let the built-in
        tool-calling loop handle invocation, retries, and stopping
        conditions.
      </>
    ),
  },
];

function Feature({title, icon, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className={styles.card}>
        <div className={styles.iconWrap}>
          <span className={styles.icon}>{icon}</span>
        </div>
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
