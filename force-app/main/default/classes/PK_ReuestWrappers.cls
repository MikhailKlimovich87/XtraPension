public class PK_ReuestWrappers {

    public class FindApplicationDataWrapper {
        public String applicationNumber;
        public String email;

        public FindApplicationDataWrapper(String inputData) {
            FindApplicationDataWrapper wrapper = (FindApplicationDataWrapper) JSON.deserialize(inputData, FindApplicationDataWrapper.class);
            this.applicationNumber = wrapper.applicationNumber;
            this.email = wrapper.email;
        }
    }
}